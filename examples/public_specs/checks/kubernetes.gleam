//// Decodes and re-encodes a Pod through the generated Kubernetes types.
////
//// Quantity (`oneOf: [string, number]`), IntOrString (`oneOf: [integer,
//// string]`) and Time (a `string` alias) are the shapes from nori#62: they had
//// no decoder or encoder although the Pod's decoder called them.

import generated/types
import gleam/io
import gleam/json
import gleam/string

const pod = "{
  \"apiVersion\": \"v1\",
  \"kind\": \"Pod\",
  \"metadata\": {\"name\": \"web\", \"creationTimestamp\": \"2024-01-01T00:00:00Z\"},
  \"spec\": {
    \"containers\": [{
      \"name\": \"nginx\",
      \"image\": \"nginx:1.27\",
      \"livenessProbe\": {\"httpGet\": {\"port\": \"http\", \"path\": \"/\"}},
      \"readinessProbe\": {\"httpGet\": {\"port\": 8080}},
      \"resources\": {
        \"limits\": {\"cpu\": \"500m\", \"memory\": \"128Mi\"},
        \"requests\": {\"cpu\": 1, \"memory\": 0.5}
      }
    }]
  }
}"

pub fn main() {
  let assert Ok(decoded) =
    json.parse(pod, types.io_k8s_api_core_v1_pod_decoder())
  let inspected = string.inspect(decoded)
  let encoded = json.to_string(types.encode_io_k8s_api_core_v1_pod(decoded))

  // Each union decodes to the member the JSON holds, a whole number included.
  expect(inspected, "StringVariant(\"500m\")")
  expect(inspected, "FloatVariant(1.0)")
  expect(inspected, "FloatVariant(0.5)")
  expect(inspected, "StringVariant(\"http\")")
  expect(inspected, "IntVariant(8080)")
  // And encodes back to the same JSON type.
  expect(encoded, "\"creationTimestamp\":\"2024-01-01T00:00:00Z\"")
  expect(encoded, "\"limits\":{\"cpu\":\"500m\",\"memory\":\"128Mi\"}")
  expect(encoded, "\"port\":\"http\"")
  expect(encoded, "\"port\":8080")
  io.println("pod round-trips")
}

fn expect(haystack: String, needle: String) -> Nil {
  case string.contains(haystack, needle) {
    True -> Nil
    False -> panic as { "expected " <> needle <> " in " <> haystack }
  }
}
