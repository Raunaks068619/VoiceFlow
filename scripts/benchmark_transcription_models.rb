#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "securerandom"
require "time"

options = {
  limit: 10,
  runs: File.expand_path("~/Library/Application Support/Vordi/runs"),
  output: "transcription-benchmark.json"
}
OptionParser.new do |parser|
  parser.banner = "Usage: benchmark_transcription_models.rb [options]"
  parser.on("--limit N", Integer, "Latest recordings to compare (default: 10)") { |v| options[:limit] = v }
  parser.on("--runs PATH", "Vordi runs directory") { |v| options[:runs] = v }
  parser.on("--references PATH", "JSON object: run-folder name -> verified transcript") { |v| options[:references] = v }
  parser.on("--output PATH", "Result JSON path") { |v| options[:output] = v }
end.parse!

api_key = ENV.fetch("OPENAI_API_KEY", "").strip
abort "OPENAI_API_KEY is required. Add the same key to Vordi Settings, then export it before benchmarking." if api_key.empty?

references = options[:references] ? JSON.parse(File.read(options[:references])) : {}
audio_files = Dir.glob(File.join(options[:runs], "*", "audio.wav"))
  .sort_by { |path| File.mtime(path) }
  .last(options[:limit])
abort "No audio.wav files found under #{options[:runs]}" if audio_files.empty?

def normalize_words(text)
  text.downcase.scan(/[\p{L}\p{N}']+/)
end

def edit_distance(left, right)
  previous = (0..right.length).to_a
  left.each_with_index do |left_word, i|
    current = [i + 1]
    right.each_with_index do |right_word, j|
      current << [
        current[j] + 1,
        previous[j + 1] + 1,
        previous[j] + (left_word == right_word ? 0 : 1)
      ].min
    end
    previous = current
  end
  previous.last
end

def word_error_rate(reference, candidate)
  reference_words = normalize_words(reference)
  return nil if reference_words.empty?

  edit_distance(reference_words, normalize_words(candidate)).fdiv(reference_words.length)
end

def transcribe(path, model, api_key)
  boundary = "VordiBenchmark#{SecureRandom.hex(12)}"
  audio = File.binread(path)
  body = +""
  body.force_encoding(Encoding::BINARY)
  [["model", model], ["response_format", "json"], ["temperature", "0"]].each do |name, value|
    body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
  end
  body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n"
  body << "Content-Type: audio/wav\r\n\r\n"
  body << audio
  body << "\r\n--#{boundary}--\r\n"

  uri = URI("https://api.openai.com/v1/audio/transcriptions")
  request = Net::HTTP::Post.new(uri)
  request["Authorization"] = "Bearer #{api_key}"
  request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
  request.body = body
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) { |http| http.request(request) }
  latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  payload = JSON.parse(response.body)
  raise "#{model} failed (HTTP #{response.code}): #{payload.dig("error", "message") || response.body}" unless response.is_a?(Net::HTTPSuccess)

  { "model" => model, "text" => payload.fetch("text"), "latency_ms" => latency_ms }
end

models = %w[gpt-4o-mini-transcribe gpt-4o-transcribe]
results = audio_files.map.with_index do |audio_path, index|
  run_id = File.basename(File.dirname(audio_path))
  warn "[#{index + 1}/#{audio_files.length}] #{run_id}"
  reference = references[run_id]
  candidates = models.map do |model|
    result = transcribe(audio_path, model, api_key)
    result["wer"] = word_error_rate(reference, result["text"]) if reference
    result
  end
  {
    "run_id" => run_id,
    "audio_path" => audio_path,
    "reference" => reference,
    "model_disagreement_rate" => word_error_rate(candidates[0]["text"], candidates[1]["text"]),
    "candidates" => candidates
  }
end

summary = models.to_h do |model|
  candidates = results.flat_map { |run| run["candidates"] }.select { |candidate| candidate["model"] == model }
  wers = candidates.filter_map { |candidate| candidate["wer"] }
  [
    model,
    {
      "mean_latency_ms" => (candidates.sum { |candidate| candidate["latency_ms"] }.fdiv(candidates.length)).round,
      "mean_wer" => wers.empty? ? nil : wers.sum.fdiv(wers.length)
    }
  ]
end

report = {
  "created_at" => Time.now.iso8601,
  "quality_note" => references.empty? ? "Add --references for WER; model disagreement alone is not a quality score." : "WER uses verified reference transcripts.",
  "summary" => summary,
  "runs" => results
}
File.write(options[:output], JSON.pretty_generate(report) + "\n")
puts "Wrote #{options[:output]}"
