module CnsStatemachine
  module Action
    class Process
      attr_accessor :active_object
      attr_accessor :event_handler

      def initialize event_handler
        @event_handler = event_handler
        @active_object = event_handler.active_object
      end
  
      def execute event_instance, context
      end
  
      def get_esv name
        event_handler.state.esv[name]
      end
    end
    
    class EvalProcess < Process
      attr_accessor :proc

      def initialize event_handler, context = nil
        super event_handler
        @proc = nil
      end
      
      def execute event_instance, context
        if @proc.blank?
          @proc = eval "Proc.new do |esvs, event_name, params| #{context}; end"
        end
        
        esvs = {}
        params = {}
        
        event_handler.parent_state.esvs.each{|esv|esvs[esv.name] = esv.parameter.get}
        event_instance.event_data.parameters.each{|name, value|params[name] = value}
        
        result = @proc.call esvs, event_instance.event_type.name, params
        
        # save back esv vars
        event_handler.parent_state.esvs.each do |esv|
          esv.parameter.set(esvs[esv.name]) if esvs.include?(esv.name) && esvs[esv.name] != esv.parameter.get
        end
        
        result 
      end
    end
  end
end
