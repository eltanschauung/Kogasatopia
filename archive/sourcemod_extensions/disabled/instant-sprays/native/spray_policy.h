// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>
namespace sprays {
constexpr size_t MaxBytes=512*1024;
bool SelectedPath(const std::string &input,std::string &canonical);
bool ValidTexture(const std::vector<uint8_t> &data,std::string &error);
// Change reserved padding only, giving the fixed delivery path a fresh stable CRC.
void CanonicalTexture(std::vector<uint8_t> &data);
uint32_t Crc(const std::vector<uint8_t> &data);
std::string Hex(uint32_t crc);
std::string CachePath(uint32_t crc);
}
