require "bundler/setup"
require "sinatra"
require_relative "helpers"
require "tmpdir"
require "uri"
require "open-uri"
require 'mime/types'
require "openai"
require "pry"

OpenAI.configure do |config|
  config.access_token = "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"
end

# Healthcheck for Kamal
get("/up") { "✓" }

post "/email" do
  json = extract_json_from(request)
  puts json.inspect
  if json['body_plain']
    from = json['from']
    if from != "mikewadhera@gmail.com"
      puts "Not from mike's gmail. Ignoring forwarding"
      return "ok"
    end
    subject = json['subject']
    body = json['body_plain']
    message = "From #{from} -- #{subject}: #{body}"
    send_as_bot(:email, message)
  end
  "ok"
end

post "/phone" do
  json = extract_json_from(request)
  puts json.inspect
  if json['type'] == 'message.received'
    # Text
    from = json['data']['object']['from']
    body = json['data']['object']['body']
    message = "💬 #{from}: #{body}"
    send_as_bot(:phone, message)
  elsif json['type'] == 'call.completed'
    # Call
    from = json['data']['object']['from']
    vmail_url = json['data']['object']['voicemail']['url']
    download_file(vmail_url) do |path|
      body = transcribe(path)
      message = "📞 #{from}: #{body}"
      send_as_bot(:phone, message)
    end
  end
  "ok"
end

MIN_ZOOM_BYTES = 30 * 1024 # 30kb
post "/zoom" do
  json = extract_json_from(request)
  puts json.inspect
  if json['download_url']
    download_url = json['download_url']
    transcript_url = json['transcript_url']
    download_file(download_url) do |path|
      if File.size?(path) > MIN_ZOOM_BYTES
        send_as_bot(:zoom, "", path)
        download_file(transcript_url) do |t_path|
          transcript = File.read(t_path)
          message = summarize(transcript, "Summarize the following zoom transcript in 3-5 short sentences. You don't need to mention it was a zoom call")
          sleep 1
          send_as_bot(:zoom, message)
        end
      else
        puts "File size too small, not sending"
      end  
    end
  end
  "ok"
end

post "/bots/phone" do
  json = extract_json_from(request)
  puts json.inspect
  "ok"
end

post "/bots/email" do
  puts(extract_json_from(request).inspect)
end

post "/bots/zoom" do
  puts(extract_json_from(request).inspect)
end

post "/bots/medical" do
  json = extract_json_from(request)
  puts json.inspect

  assistant_id = "asst_6xWtnKPbpgEdz2YH5ex9pdsb"
  prompt = json['message']['body']['plain'] # "Email from: michael scott subject: what is my deductible?"
  
  answer = ask_assistant(assistant_id, prompt)
  puts answer.inspect
  answer
end

post "/bots/cobra" do
  json = extract_json_from(request)
  puts json.inspect

  assistant_id = "asst_A0Q6JIBNjQP3IXmAEj9OGc6H"
  prompt = json['message']['body']['plain'] # from: michael scott subj: cobra body: hey when does my cobra coverage start?
  
  answer = ask_assistant(assistant_id, prompt)
  puts answer.inspect
  answer
end

not_found do
  'This is nowhere to be found.'
end

error do
  'Something went wrong.'
end
