require_relative '../mailers'
require_relative '../zendesk_read'
require_relative '../monitor_counts'
require_relative '../monitor_configuration'
include MonitorConfiguration

require 'date'

test_config = MONITOR_CONFIG
test_config[:sleep_time] = 0.0001

RSpec.describe MonitorCounts do
	
	let(:config) { 
    test_config
   }

	let(:monitor_views) { [
      {view_id: 11111111,
        alert_issue: 'notably high number of tickets via web in past hour',
        to: 'dev@example.com',
        freq: 'hourly',
        compare: 'gte',
        threshold: 200 },
      {view_id: 22222222,
        alert_issue: 'notably low number of tickets via web in past two hours',
        to: 'dev@example.com',
        freq: 'hourly',
        compare: 'lte', 
        threshold: 300 },
      {view_id: 22222222,
        alert_issue: 'notably high number of tickets via web in past two hours',
        to: 'dev@example.com',
        freq: 'hourly',
        compare: 'gte', 
        threshold: 500 },
    ] }

	let(:monitor_views2) { [
      {view_id: 11111111,
        alert_issue: 'notably high number of tickets via web in past hour',
        to: 'dev@example.com',
        freq: 'hourly',
        compare: 'gte',
        threshold: 200 },
      {view_id: 22222222,
        alert_issue: 'daily 5pm ticket count report',
        to: 'dev@example.com',
        freq: 'daily',
        type: 'report',
        offset: 20 },
    ] }

  let(:read_views1) { 
      {:view_counts=> [
      {:view_id=>11111111, 
      :value=>100, 
      :fresh=>false},
      {:view_id=>22222222, 
      :value=>400, 
      :fresh=>false}    
      ], 
      :next_page=>nil, :previous_page=>nil, :count=>1}
    }


	let(:mailer) { instance_double(Mailer) }
	let(:datasource) { instance_double(ZendeskRead) }
	let(:monitor) { MonitorCounts.new(datasource, mailer, config) }  

  describe "#check_counts" do

  	context "Zendesk doesn't return view data" do
  		it "sends error alert" do
  			allow(datasource).to receive(:view_counts).and_return({"error": "Couldn't authenticate you"})  
  			expect(mailer).to receive(:email).with(hash_including(subject: config[:event_subject_prefix]+"Couldn't authenticate you"))
  			monitor.check_counts( [{view_id: 11111111, freq: 'hourly'}] ) 
  		end
  	end

    context "Views remain stale" do
      it "sends alerts for stale views" do
  			allow(datasource).to receive(:view_counts).and_return(read_views1)
  			r1 = config[:event_subject_prefix]+"view counts not fresh for view 11111111"
  			r2 = config[:event_subject_prefix]+"view counts not fresh for view 22222222"
  			expect(mailer).to receive(:email).with(hash_including(subject: r1))
  			expect(mailer).to receive(:email).with(hash_including(subject: r2)).twice  			
  			monitor.check_counts( monitor_views ) 
  		end
    end

    context "View counts normal after one stale read" do
      it "no alert" do
        call_num = 0
   			allow(datasource).to receive(:view_counts) {
   			  call_num += 1
 			    if 1 == call_num
   			    read_views1
 			    else
   			    read_views1[:view_counts][0][:fresh] = true
   			    read_views1[:view_counts][1][:fresh] = true
            read_views1
          end
   			}
  			expect(mailer).not_to receive(:email)			
  			monitor.check_counts( monitor_views ) 
      end
    end

    context "One view count high after one stale read, other remains stale" do
      it "send double alert" do
        call_num = 0
   			allow(datasource).to receive(:view_counts) {
   			  call_num += 1
 			    if 1 == call_num
   			    read_views1
 			    else
   			    read_views1[:view_counts][0][:fresh] = true
    			  read_views1[:view_counts][0][:value] = 300  			    
   			    read_views1[:view_counts][1][:fresh] = false
            read_views1
          end
   			}
  			expect(mailer).to receive(:email).with(hash_including(subject: config[:event_subject_prefix]+"notably high number of tickets via web in past hour")) 
        r1 = config[:event_subject_prefix]+"view counts not fresh for view 22222222"  			
   			expect(mailer).to receive(:email).with(hash_including(subject: r1)).twice  			
  			monitor.check_counts( monitor_views ) 
      end
    end

    context "After one stale read, one view above, one below thresholds" do
      it "send double alert" do
        call_num = 0
   			allow(datasource).to receive(:view_counts) {
   			  call_num += 1
 			    if 1 == call_num
   			    read_views1
 			    else
   			    read_views1[:view_counts][0][:fresh] = true
    			  read_views1[:view_counts][0][:value] = 300  			    
   			    read_views1[:view_counts][1][:fresh] = true
    			  read_views1[:view_counts][1][:value] = 200  	   			    
            read_views1
          end
   			}
  			expect(mailer).to receive(:email).with(hash_including(subject: config[:event_subject_prefix]+"notably high number of tickets via web in past hour"))  			
   			expect(mailer).to receive(:email).with(hash_including(subject: config[:event_subject_prefix]+"notably low number of tickets via web in past two hours"))  			
  			monitor.check_counts( monitor_views ) 
      end
    end
    
    context "daily weekday count below threshold Monday morning" do
      let(:monitor_views2) { [
        {view_id: 33333333,
          alert_issue: 'notably low number of tickets via web in past day (excluding weekends)',
          freq: 'daily',
          days_wk: (1..5).to_a,
          compare: 'lte',
          threshold: 500, 
          to: 'dev@example.com'},
        ] }    
      let(:read_views2) { 
          {:view_counts=> [
          {:view_id=>33333333, 
          :value=>410, 
          :fresh=>true}
          ], 
          :next_page=>nil, :previous_page=>nil, :count=>1}
        }      
      it "sends alert for low count Monday but not Sunday" do
  			allow(datasource).to receive(:view_counts).and_return(read_views2)        
  			expect(mailer).to receive(:email).with(hash_including(subject: config[:event_subject_prefix]+"notably low number of tickets via web in past day (excluding weekends)"))  
  			monitor.check_counts( monitor_views2, DateTime.new(2016,7,4,0) ) 
  			expect(mailer).not_to receive(:email)	
  			monitor.check_counts( monitor_views2, DateTime.new(2016,7,3,0) )   			
  		end
  	end

    context "report spec with one stale read and no events" do
      it "send report" do
        call_num = 0
   			allow(datasource).to receive(:view_counts) {
   			  call_num += 1
 			    if 1 == call_num
   			    read_views1
 			    else
   			    read_views1[:view_counts][0][:fresh] = true
    			  read_views1[:view_counts][0][:value] = 100  			    
   			    read_views1[:view_counts][1][:fresh] = true
    			  read_views1[:view_counts][1][:value] = 200  	   			    
            read_views1
          end
   			  }
   			expect(mailer).to receive(:email).with(hash_including(subject: config[:report_subject_prefix] + monitor_views2[1][:alert_issue]))  			
  			monitor.check_counts( monitor_views2, DateTime.new(2016,7,5,20) ) 
      end
    end
  			
	end
	
	describe "#alert_threshold" do
	  it "sends alerts for fresh, non-alerted views crossing threshold" do
 	    monitor_views[0][:fresh] = false
 	    monitor_views[1][:fresh] = true
		  monitor_views[1][:value] = 400  	  
 	    monitor_views[2][:fresh] = true
		  monitor_views[2][:value] = 600  
			expect(mailer).to receive(:email).with(hash_including(subject: config[:event_subject_prefix]+"notably high number of tickets via web in past two hours"))
			monitor.alert_threshold( monitor_views )
		end
	end
	
	describe "#alert_stale" do

	  it "sends alerts for stale views" do
 	    monitor_views[0][:fresh] = false
 	    monitor_views[1][:fresh] = false
 	    monitor_views[2][:fresh] = false
 			expect(mailer).to receive(:email).with(hash_including(subject: config[:event_subject_prefix]+"view counts not fresh for view 11111111"))  
			expect(mailer).to receive(:email).with(hash_including(subject: config[:event_subject_prefix]+"view counts not fresh for view 22222222")).twice
			monitor.alert_stale( monitor_views )
		end
		
		it "doesn't send alert if no stale view" do
 	    monitor_views[0][:fresh] = true
 	    monitor_views[1][:fresh] = true
 	    monitor_views[2][:fresh] = true		  
			expect(mailer).not_to receive(:email)
			monitor.alert_stale( monitor_views )			
    end
    
	end	
	
	describe "#send_alert" do

	  context "argument not a hash" do
	    it "sends alert about improper call to send_alert" do
			  expect(mailer).to receive(:email).with(hash_including(subject: config[:event_subject_prefix]+"improper call to send_alert"))
			  monitor.send_alert( 0 )
			end
		end

		context "argument hash includes neither :fresh nor :error key" do
      it "sends alert about unspecified error" do
			  expect(mailer).to receive(:email).with(hash_including(subject: config[:event_subject_prefix]+"unspecified alerting system error"))
			  monitor.send_alert( {} )
			end
		end      

	end

  describe ".parse_freq" do
    context "given 'hour-2'" do
      it "it returns ['hour', 2]" do
        expect(monitor.parse_freq(freq: 'hour-2')).to eql(['hour',2])
      end
    end
    
    context "given 'day-14'" do
      it "it returns ['day', 14]" do
        expect(monitor.parse_freq(freq: 'day-14')).to eql(['day',14])
      end
    end
    
    context "weekly" do
      it "it returns ['day', 7]" do
        expect(monitor.parse_freq(freq: 'weekly')).to eql(['day',7])
      end
    end
    
    context "hourly" do
      it "it returns ['hour', 1]" do
        expect(monitor.parse_freq(freq: 'hourly')).to eql(['hour',1])
      end
    end
    
  end

  describe ".validate_specs" do
    silent = true
    
    context "all monitoring view specs correct with default event" do
      it "passes validation" do
        expect(monitor.validate_specs( monitor_views, silent )).to eql(true)
      end
    end

    context "monitoring with a correct report spec" do
      it "passes validation" do
        expect(monitor.validate_specs( monitor_views2, silent )).to eql(true)
      end
    end      

    context "view specs not an array of hashes" do
      it "falls validation" do
        expect(monitor.validate_specs( 0, silent )).to eql(false)
        expect(monitor.validate_specs( {}, silent )).to eql(false)  
        expect(monitor.validate_specs( [0], silent )).to eql(false)
      end
    end

    context "freq missing in some spec" do 
      it "falls validation" do      
        expect(monitor.validate_specs( monitor_views, silent )).to eql(true)
        monitor_views[1][:freq] = nil
        expect(monitor.validate_specs( monitor_views, silent )).to eql(false)
      end
    end
    
    context "threshold included in report spec" do
      it "falls validation" do  
        monitor_views[2][:type] = 'report'        
        expect(monitor.validate_specs( monitor_views, silent )).to eql(false)
      end
    end
    
  end

  describe "#select_monitoring" do
    let(:t) { Time.new(2016,6,20,17) }
    
    context "at time with odd-numbered hour" do
      it "returns only hourly monitoring specs" do
        expect(monitor.select_monitoring(monitor_views, t).length).to eql(3)
        monitor_views[0][:freq] = 'hour-2'      
        expect(monitor.select_monitoring(monitor_views, t).length).to eql(2)
      end
    end
    
    context "monitoring spec limits to Sunday" do
      it "spec isn't returned on a day other than Sunday" do
        expect(monitor.select_monitoring(monitor_views, t).length).to eql(3)
        monitor_views[1][:days_wk] = [0]
        expect(monitor.select_monitoring(monitor_views, t).length).to eql(2)
        tn = Time.new(2016,6,19,17) 
        expect(monitor.select_monitoring(monitor_views, tn).length).to eql(3)        
      end
    end
    
    context "daily monitoring limited to weekdays" do
      it "spec returned only on 0 hour of weekday" do
        monitor_views[1][:freq] = 'daily'
        monitor_views[1][:days_wk] = (1..5).to_a
        expect(monitor.select_monitoring(monitor_views, t).length).to eql(2)
        tn = Time.new(2016,6,20,0)
        expect(monitor.select_monitoring(monitor_views, tn).length).to eql(3)
        tn = Time.new(2016,6,19,0)        
        expect(monitor.select_monitoring(monitor_views, tn).length).to eql(2)
      end
    end
    
    context "monitoring spec includes a holiday exclusion" do
      it "spec is excluded on that date" do
        monitor_views[1][:holidays] = ["2016-06-20"]   
        expect(monitor.select_monitoring(monitor_views, t).length).to eql(2) 
      end
    end

  end

end

RSpec.describe ErrorReporter do
  describe "#add" do
    it "appends error to error list" do
      errors = ErrorReporter.new
      errors.error_prefix = "prefix"
      errors.add "error"
      expect(errors.list).to eql("prefix: error\n")
    end
  end
end