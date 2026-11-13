/*
 * Copyright (C) 2026 The LineageOS Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#define LOG_TAG "KukuiLightSensor"

#include "LightSensor.h"

// No android-base here: its macros.h redefines ATTRIBUTE_UNUSED, which the
// libxml2 headers behind Sensor.h already define.
#include <dirent.h>
#include <fcntl.h>
#include <hardware/sensors.h>
#include <log/log.h>
#include <unistd.h>
#include <utils/SystemClock.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <thread>
#include <vector>

namespace android::hardware::sensors::V2_1::subhal::implementation {

using ::android::hardware::sensors::V1_0::SensorFlagBits;

namespace {

// IIO device names that provide in_illuminance_input in lux.
constexpr const char* kLightDeviceNames[] = {"cros-ec-light"};

// The EC samples the sensor itself; reading the node is an EC transaction.
// 5 Hz is plenty for display brightness.
constexpr int64_t kDefaultPeriodNs = 200'000'000;
constexpr int32_t kMinDelayUs = 100'000;
constexpr int32_t kMaxDelayUs = 1'000'000;

// Reads a small sysfs attribute, without the trailing newline.
bool readSysfs(const std::string& path, std::string* out) {
    const int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return false;
    char buf[64];
    const ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (n <= 0) return false;
    out->assign(buf, n);
    while (!out->empty() && (out->back() == '\n' || out->back() == ' ')) out->pop_back();
    return true;
}

}  // namespace

LightSensor* LightSensor::build(int32_t sensorHandle, ISensorsEventCallback* callback) {
    std::unique_ptr<DIR, decltype(&closedir)> dir(opendir(DEFAULT_IIO_DIR), closedir);
    if (!dir) return nullptr;

    while (struct dirent* ent = readdir(dir.get())) {
        if (strncmp(ent->d_name, "iio:device", strlen("iio:device")) != 0) continue;
        const std::string base = std::string(DEFAULT_IIO_DIR) + ent->d_name;
        std::string name;
        if (!readSysfs(base + "/name", &name)) continue;
        for (const char* candidate : kLightDeviceNames) {
            if (name != candidate) continue;
            const std::string input = base + "/in_illuminance_input";
            if (access(input.c_str(), R_OK) != 0) {
                ALOGE("%s has no readable %s", name.c_str(), input.c_str());
                continue;
            }
            ALOGI("ambient light sensor %s at %s", name.c_str(), input.c_str());
            return new LightSensor(sensorHandle, callback, name, input);
        }
    }
    return nullptr;
}

LightSensor::LightSensor(int32_t sensorHandle, ISensorsEventCallback* callback,
                         const std::string& name, const std::string& inputPath)
    : SensorBase(sensorHandle, callback, SensorType::LIGHT), mInputPath(inputPath) {
    mSensorInfo.name = name;
    mSensorInfo.typeAsString = SENSOR_STRING_TYPE_LIGHT;
    mSensorInfo.maxRange = 65535.0f;
    mSensorInfo.resolution = 1.0f;
    mSensorInfo.power = 0.1f;
    mSensorInfo.minDelay = kMinDelayUs;
    mSensorInfo.maxDelay = kMaxDelayUs;
    mSensorInfo.flags = static_cast<uint32_t>(SensorFlagBits::ON_CHANGE_MODE);
    mSamplingPeriodNs = kDefaultPeriodNs;
    mSensorThread.start();
}

void LightSensor::batch(int32_t samplingPeriodNs) {
    const int64_t period = std::clamp(static_cast<int64_t>(samplingPeriodNs),
                                      static_cast<int64_t>(kMinDelayUs) * 1000,
                                      static_cast<int64_t>(kMaxDelayUs) * 1000);
    {
        auto lck = mSensorThread.lock();
        mSamplingPeriodNs = period;
    }
    mSensorThread.notifyAll();
}

void LightSensor::activate(bool enable) {
    {
        auto lck = mSensorThread.lock();
        if (mIsEnabled == enable) return;
        mIsEnabled = enable;
        if (enable) mReportNext = true;
    }
    mSensorThread.notifyAll();
}

Result LightSensor::flush() {
    Result result = SensorBase::flush();
    if (result == Result::OK) mReportNext = true;
    return result;
}

bool LightSensor::readLux(float* lux) const {
    std::string text;
    if (!readSysfs(mInputPath, &text)) return false;
    const char* begin = text.c_str();
    char* end = nullptr;
    const float value = strtof(begin, &end);
    if (end == begin || !std::isfinite(value) || value < 0.0f) return false;
    *lux = value;
    return true;
}

void LightSensor::report(float lux) {
    Event event{};
    event.sensorHandle = mSensorInfo.sensorHandle;
    event.sensorType = SensorType::LIGHT;
    event.timestamp = ::android::elapsedRealtimeNano();
    event.u.scalar = lux;
    std::vector<Event> events{event};
    mCallback->postEvents(events, mCallback->createScopedWakelock(isWakeUpSensor()));
}

void LightSensor::pollSensor() {
    mSensorThread.wait([this] { return mIsEnabled || mSensorThread.isStopped(); });
    if (mSensorThread.isStopped()) return;

    float lux = 0.0f;
    if (readLux(&lux)) {
        const bool changed =
                mLastLux < 0.0f || std::fabs(lux - mLastLux) >= std::max(1.0f, mLastLux * 0.02f);
        if (mReportNext.exchange(false) || changed) {
            mLastLux = lux;
            report(lux);
        }
    }

    // Sleep one period in short steps so disable and shutdown are seen quickly.
    const auto deadline =
            std::chrono::steady_clock::now() + std::chrono::nanoseconds(mSamplingPeriodNs);
    while (mIsEnabled && !mSensorThread.isStopped() &&
           std::chrono::steady_clock::now() < deadline) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
}

}  // namespace android::hardware::sensors::V2_1::subhal::implementation
