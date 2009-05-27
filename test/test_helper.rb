require 'stringio'
require 'test/unit'
require File.dirname(__FILE__) + '/../lib/cns_statemachine'

class TestCreationCore < CnsBase::Cluster::ClusterCore
  def initialize publisher
    super publisher
  end
  
  def dispatch signal
    if signal.is_a?(CnsBase::Cluster::ClusterCreationSignal)
      CnsBase.logger.fatal(("TestCreationCore: " + ("*" * 10) + signal.class.name)) if CnsBase.logger.fatal?
      CnsBase.logger.fatal(("TestCreationCore: " + ("*" * 10) + signal.params.inspect)) if CnsBase.logger.fatal?
    end
  end
end

BENCHMARK_TEST = {
  :states =>
  {
    :start =>
    {
      :esvs => 
      {
        :counter => {:default => 0},
        :time => {:default => nil, :ok_null => true}
      },
      :defer => [:event_1],
      :on_events => 
      {
        CnsStatemachine::AO::ActiveObject::SIG_STATE_ENTRY =>
        {
          :context => "esvs[:time] = Time.now",
          :publish => [{:event_2 => {}}]
        },
        :event_request =>
        {
          :context => "esvs[:counter] += 1",
          :publish => 
          [
            {
              :event_response => 
              {
                :setters => 
                {
                  :var => [:esv, :counter],
                  :var2 => "*" * 100000
                }
              }
            }
          ]
        },
        :event_2 =>
        [
          {
            :guard => "(Time.now.to_f - esvs[:time].to_f) < 1.0",
            :context => "esvs[:counter] += 1",
            :publish => [{:event_2 => {}}]
          },
          {
            :guard => "(Time.now.to_f - esvs[:time].to_f) >= 1.0",
            :context => "puts((esvs[:counter] / 1.0).to_s + ' events per sec')",
            :transition => :final
          },
        ]
      },
      :states =>
      {
        :final => 
        {
          :orthogonal_states =>
          {
            :ortho => 
            {
              :on_events => 
              {
                CnsStatemachine::AO::ActiveObject::SIG_STATE_ENTRY =>
                {
                  :context => "CnsBase.logger.info('entered ORTHOGONAL STATE') if CnsBase.logger.info?"
                },
                :event_1 =>
                {
                  :context => "CnsBase.logger.info('orthogonal state event 1') if CnsBase.logger.info?"
                }
              }
            }
          },
          :external =>
          {
            :class => TestCreationCore,
            :params => {},
            :uri => "/b",
          },
          :on_events =>
          {
            CnsStatemachine::AO::ActiveObject::SIG_STATE_ENTRY =>
            {
              :context => "CnsBase.logger.info('entered final state') if CnsBase.logger.info?"
            },
            :event_1 =>
            {
              :context => "puts((esvs[:counter] / 1.0).to_s + ' events per sec FROM DEFERED ELEMENT')"
            }
          }
        }
      }
    }
  },
  :event_types =>
  {
    :event_1 => {},
    :event_2 => {},
    :event_request => {},
    :event_response => 
    {
      :params =>
      {
        :var => { :default => -1 },
        :var2 => { :default => -1 }
      }
    }
  }
}

#:event_response =>
#{
#  :context => "puts 'event_response: ', params[:var]",
#  :publish => [{:event_2 => {}}]
#},

SIMPLE_TEST = {
  :states =>
  {
    :start =>
    {
      :on_events => 
      {
        :event_1 =>
        {
          :transition => :state2
        }
      },
      :states =>
      {
        :state2 =>
        {
          :on_events =>
          {
            CnsStatemachine::AO::ActiveObject::SIG_STATE_ENTRY =>
            {
              :context => "puts 'ENTERED STATE 2'"
            }
          }
        }
      }
    }
  },
  :event_types =>
  {
    :event_1 => {},
    :event_request => {}
  }
}

CORE_TEST = 
{
  :class => CnsBase::Cas::ClusterApplicationServer,  
  :params => 
  [
    {
      :class => CnsBase::Stub::StubControlClusterCore,
      :uri => "/stub_control_cluster"
    },
    {
      :class => CnsStatemachine::ClusterCore::StatemachineClusterCore,
      :params => BENCHMARK_TEST,
      :uri => "/a"
    }
  ]
}

=begin
class TestStub < CnsBase::Stub::StubAccessSupport
  cns_method :event_request, [:a, :b] do |name, params|
    params
  end
  
  def initialize
    super "/a"
  end
end
=end

class TestStub < CnsBase::Stub::StubAccessSupport
  def initialize stub_control_cluster_address
    super stub_control_cluster_address
  end
  
  def lustig
    invoke( 
      CnsBase::Address::AddressRouterSignal.new(
        CnsBase::Signal.new(
          :event_request, 
          {}
        ),
        CnsBase::Address::PublisherSignalAddress.new( publisher ),
        CnsBase::Address::URISignalAddress.new( "/a" ) 
      ),
      :lustig_response
    ).response
  end
  
  def lustig_response request, signal
    if signal.name == :event_response
      return CnsBase::Stub::StubResponse.new(signal.params)
    end
    
    if signal.is_a?(CnsBase::ExceptionSignal)
      return CnsBase::Stub::StubResponse.new(signal.exception.message)
    end
    
    return nil
  end
  
  def send_and_forget
    params = {}
    invoke(CnsBase::Signal.new(:event_request, params))
  end
end
