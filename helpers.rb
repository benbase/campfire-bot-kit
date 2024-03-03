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

def ask_assistant(assistant_id, prompt)
  client = OpenAI::Client.new
  # Create thread
  response = client.threads.create
  thread_id = response["id"]
  puts "Thread ID: #{thread_id}"
  # Add prompt
  client.messages.create(
    thread_id: thread_id,
    parameters: {
      role: "user", # Required for manually created messages
      content: prompt
    }
  )
  # Create run
  response = client.runs.create(thread_id: thread_id,
    parameters: {
      assistant_id: assistant_id
    })
  run_id = response['id']
  puts "Run ID: #{run_id}"
  # Spin
  loop do
    response = client.runs.retrieve(id: run_id, thread_id: thread_id)
    status = response['status']

    case status
    when 'queued', 'in_progress', 'cancelling'
      puts 'Sleeping'
      sleep 0.3 # Wait and poll again
    when 'completed'
      puts "Completed"
      break # Exit loop and report result to user
    when 'requires_action'
      puts "Requires Action"
      # Handle tool calls (see below)
      tools_to_call = response.dig('required_action', 'submit_tool_outputs', 'tool_calls')
  
      my_tool_outputs = tools_to_call.map { |tool|
          # Call the functions based on the tool's name
          function_name = tool.dig('function', 'name')
          arguments = JSON.parse(
                tool.dig("function", "arguments"),
                { symbolize_names: true },
          )
          
          tool_output = case function_name
            when "get_enrollment"
              puts "Calling function"
              get_enrollment(**arguments)
            end
  
          { tool_call_id: tool['id'], output: tool_output }
      }
  
      client.runs.submit_tool_outputs(thread_id: thread_id, run_id: run_id, parameters: { tool_outputs: my_tool_outputs })
    when 'cancelled', 'failed', 'expired'
      puts response['last_error'].inspect
      break # or `exit`
    else
      puts "Unknown status response: #{status}"
      break
    end
  end
  puts "Complete"
  # Break
  messages = client.messages.list(thread_id: thread_id)
  messages["data"].each do |message|
    if message["role"] == "assistant"
      message["content"].each do |content|
        if content["type"] == "text"
          return content["text"]["value"]
        end
      end
    end
  end
  return nil
end

def get_enrollment(name:)
  return <<-EOS
    Employee Name,Enrollment Status,Medical plan,Medical plan code
    Michael Scott,Enrolled,Anthem Gold PPO,6RH1
    Angela Martin,Enrolled,Anthem Gold PPO,6RH1
    Dwight Schrute,Waived,,
    Mike Wadhera,Enrolled,Anthem Silver PPO,6RK6
  EOS
end

def download_file(download_url, &block)
  uri = URI(download_url)
  filename = File.basename(uri.path)
  tmpdir = Dir.mktmpdir
  path = File.join(tmpdir, filename)
  unless File.exist?(path)
    puts "Downloading file to #{path}"
    URI.open(download_url) do |download|
      File.open(path, "wb") do |file|
        file.write(download.read)
        file.rewind
        block.call(path)
      end
    end
  end
end

def transcribe(path)
  client = OpenAI::Client.new
  response = client.audio.transcribe(
    parameters: {
        model: "whisper-1",
        file: File.open(path, "rb"),
    })
  response['text']
end

def summarize(text, prompt='Summarize the following text in short bullets:')
  client = OpenAI::Client.new
  response = client.chat(
    parameters: {
        model: "gpt-4",
        messages: [{ role: "user", content: "#{prompt} #{text}"}]
    })
  response.dig("choices", 0, "message", "content")
end