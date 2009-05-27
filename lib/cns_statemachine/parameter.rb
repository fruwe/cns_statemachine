module CnsStatemachine
  module Parameter
    class Parameter
      attr_accessor :active_object
      attr_accessor :parameter_type
      attr_accessor :value

      def initialize parameter_type, active_object
        raise unless parameter_type
        raise unless active_object
        
        @active_object = active_object
        @parameter_type = parameter_type
        @value = nil
        
        init
      end
      
      def get
        @value
      end
      
      def name
        @parameter_type.name
      end
      
      def init
        set @parameter_type.default_value
      end
      
      def set value
        raise "10008" if @parameter_type.blank?
        
        if value
          @value = value
        elsif @parameter_type.ok_null
          @value = nil
        else
          raise([name, value.inspect].inspect)
        end
      end
    end
    
    class ParameterType
      attr_accessor :guard
      attr_accessor :default_value
      attr_accessor :name
      attr_accessor :event_type_or_state
      attr_accessor :ok_null

      def initialize
        super
        
        @guard = nil
        @default_value = nil
        @name = nil
        @event_type_or_state = nil
        @ok_null = false
      end
      
      def guard= action
        if action.is_a?(String)
          @action = lambda(action)
        else
          @action = action
        end
      end
    end
    
    class Esv < ParameterType
      attr_accessor :parameter
      attr_accessor :active_object

      def initialize active_object
        super()
        
        @active_object = active_object
        @parameter = nil
      end
      
      def reset
        @parameter = Parameter.new(self, active_object)
      end
    end
  end
end
