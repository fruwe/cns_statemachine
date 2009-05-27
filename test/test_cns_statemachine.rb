require File.dirname(__FILE__) + '/test_helper.rb'

class TestCnsStatemachine < Test::Unit::TestCase
  def setup
  end
  
  def test_truth
    assert true
  end
  
  def test_statemachine
    template SIMPLE_TEST
    template BENCHMARK_TEST
  end
  
  def test_cores
    CnsBase::Cas::CasControlHelper.init CORE_TEST
    CnsBase::Cas::CasControlHelper.confirm_start

    ts = TestStub.new "/stub_control_cluster"
    sleep 4
    puts "=====================================", ts.lustig.pretty_inspect

    sleep(4)

    CnsBase::Cas::CasControlHelper.shutdown

    puts
    puts
    puts
    puts
    puts
  end
  
private
  def template template
    puts
    puts "Test next template"
    puts
    
    active_object = CnsStatemachine::AO::ActiveObject.new

    active_object.from_yaml template
    
    active_object.attach
    while active_object.tick; end
    active_object.publish(active_object.new_event(:event_1))
    while active_object.tick; end
    active_object.publish(active_object.new_event(:event_request))
    while active_object.tick; end
    active_object.detach
  end
end
