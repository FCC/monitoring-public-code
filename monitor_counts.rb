require 'set'

require_relative 'zendesk_read'
require_relative 'mailers'


class MonitorCounts

  def initialize( datasource, mailer, config )
    @datasource, @mailer, @config = datasource, mailer, config
  end

  def validate_specs ( monitor_spec, silent = false )
    errors = ErrorReporter.new
    if Array != monitor_spec.class
      errors.add "error: monitoring views not specified as an array"
    else  
      monitor_spec.each_with_index do |view, index|
        if Hash != view.class
          errors.add "error: spec #{index} not specified as a hash"
          next
        end
        errors.error_prefix = "error in spec #{index}, for '#{view[:alert_issue]}'"
        if !view[:view_id]
          errors.add "view_id must be specified" 
        end
        if !view[:alert_issue]
          errors.add "alert issue must be specified"
        elsif 'report' == view[:type] && 78 < ( @config[:report_subject_prefix].length + view[:alert_issue].length ) 
          errors.add "report_subject_prefix  + alert issue cannot be longer than 78 characters total"        
        elsif 78 < ( @config[:event_subject_prefix].length + view[:alert_issue].length ) 
          errors.add "event_subject_prefix  + alert issue cannot be longer than 78 characters total"
        end
        if !view[:to] || !( view[:to].class == Array || view[:to].class == String )
          errors.add "to address not properly specified"
        end
        if view[:days_wk] && !( view[:days_wk].class == Array && (view[:days_wk] - Array(0..6)).empty? ) 
          errors.add "days_wk should be specified as an array with integer elements from 0 (Sunday) to 6 (Saturday)" 
        end
        if view[:hours_day] && !( view[:hours_day].class == Array && (view[:hours_day] - Array(0..23)).empty? )
          errors.add "hours_day should be specified as an array with integer elements 0 to 23"
        end
        if view[:holidays] && !( view[:holidays].class == Array && view[:hours_day].inject(true) { |v,d| v && d.class == String } ) 
          errors.add "holidays should be specified as an array of strings of the form 2016-01-02" 
        end
        if ![nil, 'event', 'report'].include?(view[:type])
          errors.add "type can only be nil (default to event), event, or report" 
        end
        if 'report' == view[:type] && ( view[:threshold] || view[:compare])
          errors.add "threshold and compare irrelevant to report type"
        end
        if ( nil == view[:type] || 'event' == view[:type] ) && !( view[:threshold] && view[:compare] )
          errors.add "threshold and compare must be include in event spec"
        end
        if !view[:freq] || !parse_freq( view )
          errors.add "freq missing or incorrectly specified"
        end
        if view[:offset] && (view[:offset]<0 || view[:offset]>23)
          errors.add "offset must be number (of hours) between 0 and 23"
        end
      end
    end
    if "" == errors.list
      puts "Monitoring spec passed validation\n\n" if !silent
      return true;
    else
      puts "Monitoring spec failed validation\n\n" if !silent
      puts errors.list if !silent
      return false
    end
  end

  def check_counts ( monitor_spec, test_time = nil )
    test_time = Time.new if !test_time
    monitor_views = select_monitoring( monitor_spec, test_time )
    ids = Set.new monitor_views.map { |view| view[:view_id] }
    try_API = 0
    counts = {}
    monitor_views.each { |record_view| record_view[:fresh] = false }
    while ids.length > 0 && (try_API += 1 ) <= @config[:api_tries]  do 
      counts = @datasource.view_counts( ids )
      if counts.key?(:view_counts)
        counts[:view_counts].each do |view|
          monitor_views.each do |record_view|
            next if record_view[:view_id] != view[:view_id]
            record_view[:fresh] = view[:fresh] if not record_view[:fresh]
            record_view[:value] = view[:value] if view[:fresh]
          end
        end
        alert_threshold( monitor_views )
        alert_report( monitor_views )
        ids = monitor_views.each_with_object( Set.new ) { |view, retry_ids| retry_ids << view[:view_id] if not view[:fresh] }
      end
      sleep @config[:sleep_time]*60  if 0 < ids.length # pause for given number of seconds before retry
    end
    if counts[:error]
      send_alert( counts )
    else  
      alert_stale( monitor_views ) if 0 < ids.length
    end
  end

  def select_monitoring( monitor_spec, datetime )
    monitor_spec.select do |view|
      freq_spec = parse_freq( view )
      offset = view[:offset] || 0 
      active = true
      if 'day' == freq_spec[0]
        active = (datetime.yday % freq_spec[1]) == 0
        active &&= ( (datetime.hour - offset) % freq_spec[1]) == 0
      elsif 'hour' == freq_spec[0]
        active = ( (datetime.hour - offset) % freq_spec[1]) == 0
      end
      active = false if view[:days_wk] && (not view[:days_wk].include?( datetime.wday )) 
      active = false if view[:hours_day] && (not view[:hours_day].include?( datetime.hour )) 
      active = false if view[:holidays] && view[:holidays].include?( datetime.strftime("%Y-%m-%d") )
      active
    end
  end

  def parse_freq( view )
    freq = view[:freq]
    freq_parsed = case freq
      when "weekly" then ["day", 7]
      when "daily" then ["hour", 24]
      when "hourly" then ["hour", 1]
      when /(^day-\d+$)|(^hour-\d+$)/ 
        string_array = freq.split("-")
        [ string_array[0], string_array[1].to_i ]
      end
    if 'weekly' == freq && view[:days_wk] 
      freq_parsed = ["hour", 24]  # daily according to days_wk
    end
    return freq_parsed
  end

  def alert_threshold( views )
  # alert for fresh views crossing threshold  
    views.each do |view|
      next if (nil != view[:type] && 'event' != view[:type] )
      next if !view[:fresh]
      next if view[:alerted]
      case view[:compare]
      when 'gte'
        alert = view[:value]>=view[:threshold]
      when 'lte'
        alert = view[:value]<=view[:threshold]
      else
        alert = false
      end
      if alert
        send_alert( view )
        view[:alerted] = true
      end
    end
  end

  def alert_report( views )
    views.each do |view|  
      next if 'report' != view[:type]
      next if !view[:fresh]
      next if view[:alerted]
      send_alert( view )
      view[:alerted] = true
    end
  end
    
  def alert_stale( views )
  # send alerts for any stale views
    views.each do |view|
      send_alert( view ) if not view[:fresh]
    end
  end
  
  def send_alert( alert_view )
    alert_mail = { subject: @config[:event_subject_prefix], body: @config[:event_body_heading] } # default form
    alert_mail[:to] = @config[:admin_email] # default destination
    if Hash != alert_view.class
      alert_mail[:subject] += "improper call to send_alert"
      alert_mail[:body] += "alert_view: #{alert_view}"
    elsif [true, false].include? alert_view[:fresh] 
      view_link = "View link: " + @config[:zendesk_url] + "/agent/filters/#{alert_view[:view_id]}"
      if alert_view[:fresh] == true
        alert_mail[:to] = alert_view[:to] 
        if 'report' == alert_view[:type] 
          # replace default event subject prefix & body heading
          alert_mail[:subject] = @config[:report_subject_prefix]
          alert_mail[:body] = @config[:report_body_heading]  
        end
        alert_mail[:subject] += alert_view[:alert_issue]
        if 'report' == alert_view[:type]
          alert_mail[:body] += "#{alert_view[:alert_issue]}: #{alert_view[:value]} tickets\n\n"
        else  
          alert_mail[:body] += "#{alert_view[:value]} tickets in view #{alert_view[:view_id]}\n\n"
          alert_mail[:body] += "comparison: #{alert_view[:compare]}, threshold: #{alert_view[:threshold]} \n"
          alert_mail[:body] += "=> #{alert_view[:alert_issue]} \n\n"
        end
        alert_mail[:body] += view_link
      else 
        alert_mail[:subject] += "view counts not fresh for view #{alert_view[:view_id]}"
        alert_mail[:body] += "Using #{@config[:api_tries]} tries, can't read fresh view count for view #{alert_view[:view_id]}. May indicate view deleted or a problem with the Zendesk platform.\n"
        alert_mail[:body] += view_link
      end
    else
      alert_mail[:subject] += alert_view[:error] ? alert_view[:error] : "unspecified alerting system error"
      alert_mail[:body] += "Zendesk down, access credentials invalid, alerting views deleted, alerting views mis-specified, or some other issue.\n"
    end 
    @mailer.email( alert_mail )
    alert_mail[:subject]
  end

end


class ErrorReporter
  attr_reader :list
  attr_accessor :error_prefix

  def initialize
    @list = ""
    @error_prefix = ""
  end

  def add( error )
    @list += @error_prefix + ": " if "" != @error_prefix
    @list += error + "\n"
  end
  
end