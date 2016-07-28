module Omnivore
  class Source
    class Unixsocket < Internal

      @socket : String?
      @connection : UNIXSocket?
      @server : UNIXServer?
      @collecting : Bool = false
      @connections = [] of IO::FileDescriptor

      def setup
        @socket = config["path"].to_s
        super
      end

      def connect
        debug "Setting up unix socket server at `#{@socket}`"
        @server = UNIXServer.new(@socket.to_s)
        collect_messages!
        super
      end

      def shutdown
        @collecting = false
        @connections.map do |con|
          con.close
        end
        srv = @server
        srv.close if srv
        super
      end

      def connection
        i_connection = @connection
        if(i_connection.nil?)
          i_connection = @connection = UNIXSocket.new(@socket.to_s)
        end
        i_connection
      end

      def server
        srv = @server
        if(srv.nil?)
          error "Server is not properly setup for receiving messages"
          raise "Server is not configured correctly!"
        else
          srv
        end
      end

      def transmit(msg : Message)
        payload = msg.data
        debug ">> #{payload.to_json}"
        connection.puts(payload.to_json)
        connection.flush
        self
      end

      def handle_connection(sock)
        unless(@connections.includes?(sock))
          debug "Registered new client socket connection `#{sock}`"
          @connections << sock
          spawn do
            while(@collecting)
              line = sock.gets
              if(line)
                debug "Received new input from client socket `#{sock}`: #{line.inspect}"
                source_mailbox.send(line.strip)
              end
            end
          end
        end
      end

      def collect_messages!
        unless(@collecting)
          @collecting = true
          spawn do
            begin
              while(@collecting)
                debug "Waiting for new client socket connection"
                sock = server.accept
                spawn{ handle_connection(sock) }
              end
              debug "Message collection has been halted"
            rescue e
              error "Socket message collection error - #{e.class}: #{e}"
            end
          end
        else
          warn "Already collecting messages from socket server"
        end
      end

    end
  end
end
