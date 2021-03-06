require "concurrent/atomics"
require "thread"

module LaunchDarkly
  class PollingProcessor
    def initialize(config, requestor)
      @config = config
      @requestor = requestor
      @initialized = Concurrent::AtomicBoolean.new(false)
      @started = Concurrent::AtomicBoolean.new(false)
      @stopped = Concurrent::AtomicBoolean.new(false)
    end

    def initialized?
      @initialized.value
    end

    def start
      return unless @started.make_true
      @config.logger.info("[LDClient] Initializing polling connection")
      create_worker
    end

    def stop
      if @stopped.make_true
        if @worker && @worker.alive?
          @worker.raise "shutting down client"
        end
        @config.logger.info("[LDClient] Polling connection stopped")
      end
    end

    def poll
      flags = @requestor.request_all_flags
      if flags
        @config.feature_store.init(flags)
        if @initialized.make_true
          @config.logger.info("[LDClient] Polling connection initialized")
        end
      end
    end

    def create_worker
      @worker = Thread.new do
        @config.logger.debug("[LDClient] Starting polling worker")
        while !@stopped.value do
          begin
            started_at = Time.now
            poll
            delta = @config.poll_interval - (Time.now - started_at)
            if delta > 0
              sleep(delta)
            end
          rescue InvalidSDKKeyError
            @config.logger.error("[LDClient] Received 401 error, no further polling requests will be made since SDK key is invalid");
            stop
          rescue StandardError => exn
            @config.logger.error("[LDClient] Exception while polling: #{exn.inspect}")
            # TODO: log_exception(__method__.to_s, exn)
          end
        end
      end
    end

    private :poll, :create_worker
  end
end
