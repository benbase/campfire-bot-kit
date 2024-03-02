require "bundler/setup"
require "sinatra"
require_relative "helpers"
require "tmpdir"
require "uri"
require "open-uri"
require 'mime/types'

# Healthcheck for Kamal
get("/up") { "✓" }

post "/inspect" do
  raise extract_json_from(request).inspect
end

post "/email" do
  json = extract_json_from(request)
  puts json.inspect
  if json['body_plain']
    from = json['from']
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
    body = json['data']['object']['voicemail']['url']
    message = "📞 #{from}: #{body}"
    send_as_bot(:phone, message)
  end
  "ok"
end

MIN_ZOOM_BYTES = 30 * 1024 # 30kb
post "/zoom" do
  json = extract_json_from(request)
  puts json.inspect
  if json['download_url']
    download_url = json['download_url']
    message = download_url
    # send_as_bot(:zoom, message)
    uri = URI(download_url)
    filename = File.basename(uri.path)
    tmpdir = Dir.mktmpdir
    video_path = File.join(tmpdir, filename)
    unless File.exist?(video_path)
      puts "Downloading file to #{video_path}"
      URI.open(download_url) do |video|
        File.open(video_path, "wb") do |file|
          file.write(video.read)
        end
      end
    end
    if File.size?(video_path) > MIN_ZOOM_BYTES
      send_as_bot(:zoom, message, video_path)
    else
      puts "File size too small, not sending"
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

not_found do
  'This is nowhere to be found.'
end

error do
  'Something went wrong.'
end
