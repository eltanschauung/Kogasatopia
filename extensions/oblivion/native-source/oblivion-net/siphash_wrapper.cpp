// Compile the unmodified CC0 reference implementation with this project's C++
// toolchain; the inherited HL2SDK flags include C++-only warning options.
extern "C" {
#include "third_party/siphash/siphash.c"
}
