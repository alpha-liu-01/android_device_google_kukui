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
#pragma once

#include <atomic>
#include <string>

#include "Sensor.h"

namespace android::hardware::sensors::V2_1::subhal::implementation {

// Ambient light from an IIO device that only exposes a processed sysfs value.
// cros-ec-light has no buffer scan elements, only in_illuminance_input in lux,
// so it cannot go through HWSensorBase. The value is polled and reported as an
// on-change LIGHT sensor.
class LightSensor : public SensorBase {
  public:
    // Returns nullptr when no supported light device is present.
    static LightSensor* build(int32_t sensorHandle, ISensorsEventCallback* callback);

    void batch(int32_t samplingPeriodNs) override;
    void activate(bool enable) override;
    Result flush() override;
    const std::string& inputPath() const { return mInputPath; }

  protected:
    void pollSensor() override;

  private:
    LightSensor(int32_t sensorHandle, ISensorsEventCallback* callback, const std::string& name,
                const std::string& inputPath);
    bool readLux(float* lux) const;
    void report(float lux);

    std::string mInputPath;
    float mLastLux = -1.0f;
    // Set on enable and flush so the current value is sent even if unchanged.
    std::atomic_bool mReportNext{true};
};

}  // namespace android::hardware::sensors::V2_1::subhal::implementation
