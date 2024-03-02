require "json"
require "pathname"
require 'net/http'
require 'uri'
require 'mime/types'

def extract_json_from(request)
  request.body.rewind
  JSON.parse(request.body.read)
end

def send_as_bot(bot, message, attachment_path = nil)
  urls = {
    phone: 'https://chief-square-ray.ngrok-free.app/rooms/3/5-AnFBPH3haO9h/messages',
    email: 'https://chief-square-ray.ngrok-free.app/rooms/3/6-8Z1IRwPRKPZj/messages',
    zoom: 'https://chief-square-ray.ngrok-free.app/rooms/3/7-YKJB5t3umVTN/messages'
  }
  url = URI.parse(urls[bot])

  request = Net::HTTP::Post.new(url.request_uri)

  if attachment_path
    filename = File.basename(attachment_path)
    file_content_type = bot == :zoom ? "video/mp4" : MIME::Types.type_for(filename).first.content_type

    boundary = "AaB03x"
    file_body = File.binread(attachment_path)
    post_body = []
    post_body << "--#{boundary}\r\n"
    post_body << "Content-Disposition: form-data; name=\"message\"\r\n\r\n"
    post_body << message
    post_body << "\r\n--#{boundary}\r\n"
    post_body << "Content-Disposition: form-data; name=\"attachment\"; filename=\"#{filename}\"\r\n"
    post_body << "Content-Type: #{file_content_type}\r\n\r\n"
    post_body << file_body
    post_body << "\r\n--#{boundary}--\r\n"

    request.body = post_body.join
    request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
  else
    request.body = message
    request["Content-Type"] = "text/plain"
  end

  response = Net::HTTP.start(url.host, url.port, use_ssl: url.scheme == 'https') do |http|
    http.request(request)
  end

  puts response.body
end
