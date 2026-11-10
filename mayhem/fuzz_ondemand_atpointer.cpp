// On-Demand at_pointer on an object, an array and a value. Input: JSON document, "\n~~\n", JSON
// Pointer. The pointer is a view straight into the input buffer (as in fuzz/fuzz_atpointer.cpp), and
// is a default-constructed std::string_view when the separator is missing.
#include "FuzzUtils.h"
#include "simdjson.h"
#include <cstddef>
#include <cstdint>
#include <string_view>
#include <utility>

namespace {

void probe(simdjson::simdjson_result<simdjson::ondemand::value> r) {
  simdjson::ondemand::value v;
  if (r.get(v)) return;
  simdjson_unused auto s = v.get_string();
}

void run(const simdjson::padded_string &json, std::string_view ptr, int which) {
  simdjson::ondemand::parser parser;
  auto doc_result = parser.iterate(json);
  simdjson::ondemand::document doc;
  if (std::move(doc_result).get(doc)) return;
  switch (which) {
  case 0: {
    simdjson::ondemand::object obj;
    if (doc.get_object().get(obj)) return;
    probe(obj.at_pointer(ptr));
  } break;
  case 1: {
    simdjson::ondemand::array arr;
    if (doc.get_array().get(arr)) return;
    probe(arr.at_pointer(ptr));
  } break;
  default: {
    simdjson::ondemand::value val;
    if (doc.get_value().get(val)) return;
    probe(val.at_pointer(ptr));
  } break;
  }
}

} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *Data, size_t Size) {
  FuzzData fd(Data, Size);
  auto strings = fd.splitIntoStrings();
  std::string_view json = strings.empty() ? std::string_view{} : strings[0];
  std::string_view ptr = strings.size() > 1 ? strings[1] : std::string_view{};
  simdjson::padded_string padded(json);
  for (int which = 0; which < 3; which++) run(padded, ptr, which);
  return 0;
}
