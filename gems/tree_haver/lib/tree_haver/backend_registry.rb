# frozen_string_literal: true

module TreeHaver
  module BackendRegistry
    module_function

    def register(backend)
      mutex.synchronize do
        backends[backend.id] = deep_dup(backend.to_h)
      end
      nil
    end

    def fetch(id)
      data = mutex.synchronize { backends[id] }
      data && BackendReference.new(**deep_dup(data))
    end

    def all
      mutex.synchronize do
        backends.values.map { |backend| BackendReference.new(**deep_dup(backend)) }
      end
    end

    def register_availability_checker(name, checker = nil, &block)
      availability_checkers[name.to_sym] = checker || block
      nil
    end

    def available?(name)
      checker = availability_checkers[name.to_sym]
      return false unless checker

      !!checker.call
    rescue StandardError
      false
    end

    def clear!
      mutex.synchronize do
        backends.clear
        availability_checkers.clear
      end
    end

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
    private_class_method :deep_dup

    def backends
      @backends ||= {} # rubocop:disable ThreadSafety/MutableClassInstanceVariable
    end
    private_class_method :backends

    def mutex
      @mutex ||= Mutex.new # rubocop:disable ThreadSafety/MutableClassInstanceVariable
    end
    private_class_method :mutex

    def availability_checkers
      @availability_checkers ||= {} # rubocop:disable ThreadSafety/MutableClassInstanceVariable
    end
    private_class_method :availability_checkers
  end
end
