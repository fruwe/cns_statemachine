require 'cns_base'

$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

module CnsStatemachine
  VERSION = '0.0.2'
  
  $COUNT = 0
  $DONE = 0
  
  class Queue
    class QueueObject
      attr_accessor :locked
      attr_accessor :object

      def initialize object
        @object = object
        @locked = false

        $COUNT += 1
      end

      def get
        @object
      end

      def locked?
        @locked
      end
    end

    def initialize
      @queue = []
      @queue.extend MonitorMixin
      @condition = @queue.new_cond
    end

    def acknowledge queue_object
      @queue.synchronize do
        $DONE += 1
#          puts "#{$DONE} / #{$COUNT}"

        raise "10000" if queue_object.blank? || !queue_object.locked? || !@queue.include?(queue_object)

        queue_object.object = nil

        @queue.delete queue_object
      end
    end

    def clear
      @queue.synchronize do
        @queue.clear
        @condition.broadcast
      end
    end

    def deferr queue_object
      @queue.synchronize do
        raise "10001" if queue_object.blank? || !queue_object.locked? || !@queue.include?(queue_object)

        queue_object.locked = false

        get(@queue.index(queue_object) + 1)
      end
    end

    def find object
      @queue.find do |queue_object|
        queue_object.object == object
      end
    end

    def get index = 0
      @queue.synchronize do
        while true
          qo = @queue[index]

          if qo.blank?
            return nil
          elsif not qo.locked?
            qo.locked = true
            return qo
          end

          index = index + 1
        end
      end
    end

    def get_or_wait time_out = 0
      result = nil

      while result == nil
        wait_for_not_empty time_out

        result = get

        break if time_out > 0
      end

      result
    end

    def empty?
      @queue.empty?
    end

    def locked?
      @queue.synchronize do
        !!@queue.find{|qo|qo.locked?}
      end
    end

    def putFIFO object
      @queue.synchronize do
        @queue.unshift(QueueObject.new(object))
        @condition.broadcast
      end
    end

    def putLIFO object
      @queue.synchronize do
        @queue.push(QueueObject.new(object))
        @condition.broadcast
      end
    end

    def size
      @queue.size
    end

    def wait_for_not_empty time_out = 0
      start = Time.new.to_i

      @queue.synchronize do
        while @queue.empty?
          left = time_out - (Time.new.to_i - start)

          return if left <= 0 && time_out > 0

          @condition.wait(left / 1000.0)
        end
      end
    end
  end
end

require 'cns_statemachine/parameter'
require 'cns_statemachine/event'
require 'cns_statemachine/action'
require 'cns_statemachine/state'
require 'cns_statemachine/ao'
require 'cns_statemachine/cluster_core'
