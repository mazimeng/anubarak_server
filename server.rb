require 'socket'
require 'time'

module Anubarak
  TYPE_DATA = 1
  TYPE_HEART_BEAT = 2
  TYPE_CLOSE = 3

  class Save
    def initialize
      @queue = Queue.new
      @subscribers = []
      @output_queue = Queue.new
    end

    def timestamp
      Time.now.strftime '%Y-%m-%d-%H'
    end

    def save(batch)
      @queue << batch
    end

    def start
      @thread = Thread.new do
        data_path = ENV['DATA_PATH'] || '/var/anubarak'
        processing_file_path = "#{data_path}/#{timestamp}.pcm"

        loop do
          batch = @queue.pop
          break if batch.length == 0

          File.open(processing_file_path, 'a') do |file|
            batch.each do |data|
              file.write data
            end
          end

          puts batch.length
          @output_queue << batch
        end
      end

      output_thread = Thread.new do
        loop do
          batch = @output_queue.pop
          break if batch.length == 0

          batch.each do |data|
            bad_clients = []
            @subscribers.each do |client|
              begin
                client.write [data.bytesize].pack("l>")
                client.write data
              rescue Exception => ex
                puts ex
                bad_clients << client
              end
            end

            @subscribers.delete_if { |s| bad_clients.include? s }
          end
        end
      end

      subscriber_listener = Thread.new do
        listener = TCPServer.open(10002)

        loop do
          client = listener.accept
          @subscribers << client
        end
      end
    end

    def stop
      @queue.push []
      @thread.join
    end
  end

  class Server
    def initialize
      @next_save = 0
      @save_rate = 30 # seconds
      @port = 10001
    end

    def listen
      save = Save.new
      save.start

      puts "listening on #{@port}"
      server = TCPServer.open(@port)

      loop do
        client = server.accept

        puts 'accepted a client'
        process client, save
        puts 'a client closed'
      end

      save.stop
    end

    def process(client, save)
      total = 0
      buffer = []
      buffer_size = 0
      max_buffer_size = 1 * 32 * 1024

      loop do
        raw_headers = client.read(8)
        break unless raw_headers

        headers = raw_headers.unpack('l>l>')
        type = headers[0]
        data_length = headers[1]

        if type == TYPE_HEART_BEAT
          puts "#{Time.now}: received heart beat #{data_length}"
        end

        if type == TYPE_DATA
          payload = client.read(data_length)
          total += payload.length
          buffer_size += payload.length

          if buffer_size + payload.length >= max_buffer_size
            save.save buffer

            buffer = []
            buffer_size = 0
          end

          buffer << payload
        end
      end

      client.close unless client.closed?

      puts "done, received: #{total}"
      save.save buffer if buffer.length > 0
    rescue Exception => e
      puts e.message
    end
  end
end

server = Anubarak::Server.new
server.listen
