module Omnivore
  class Source
    class Unixsocket < Internal

      @socket : String?
      @connection : UNIXSocket?
      @server : UNIXServer?
      @collecting : Bool = false
      @connections = [] of IO::FileDescriptor

      # Setup the source
      def setup
        @socket = config["path"].to_s
        super
      end

      # Setup the unix server and collection incoming messages
      def connect
        debug "Setting up unix socket server at `#{@socket}`"
        @server = UNIXServer.new(@socket.to_s)
        collect_messages!
        super
      end

      # Close all connections and server if running
      def shutdown
        @collecting = false
        @connections.map do |con|
          con.close
        end
        srv = @server
        srv.close if srv
        super
      end

      # Establish connection to socket
      #
      # @return [UNIXSocket]
      def connection
        i_connection = @connection
        if(i_connection.nil?)
          i_connection = @connection = UNIXSocket.new(@socket.to_s)
        end
        i_connection
      end

      # @return [UNIXServer]
      def server
        srv = @server
        if(srv.nil?)
          error "Server is not properly setup for receiving messages"
          raise "Server is not configured correctly!"
        else
          srv
        end
      end

      # Send message to source
      #
      # @param msg [Message] message to send
      # @return [self]
      def transmit(msg : Message)
        payload = msg.data
        debug ">> #{payload.to_json}"
        connection.puts(payload.to_json)
        connection.flush
        self
      end

      # Handle new client socket connection
      #
      # @param sock [IO]
      def handle_connection(sock)
        unless(@connections.includes?(sock))
          debug "Registered new client socket connection `#{sock}`"
          @connections << sock
          spawn do
            enabled = true
            while(@collecting && enabled)
              begin
                line = sock.gets
                if(line)
                  debug "Received new input from client socket `#{sock}`: #{line.inspect}"
                  source_mailbox.send(line.strip)
                end
              rescue e
                error "Client socket connection generated error - #{e.class}: #{e}"
                sock.close unless sock.closed?
                enabled = false
              end
            end
            debug "Removing client socket connection for registered list `#{sock}`"
            @connections.delete(sock)
          end
        end
      end

      # Collect messages from the UNIXServer
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
