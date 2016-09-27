# one-off job testing before scheduling chron_runner

# setup test

require_relative 'zendesk_read'
require_relative 'mailers'
require_relative 'monitor_counts'
require_relative 'monitor_configuration'

include MonitorConfiguration

datasource = ZendeskRead.new( DATASOURCE_CONFIG )

mailer_sendgrid = ViaSendGrid.new( SENDGRID_CONFIG )
mailer_term = Mailer.new( {from: 'admin@example.com'} )

monitor_to_sendgrid = MonitorCounts.new( datasource, mailer_sendgrid, MONITOR_CONFIG)
monitor_to_term = MonitorCounts.new( datasource, mailer_term, MONITOR_CONFIG )


# validate monitoring configuration

abort if !monitor_to_term.validate_specs( MONITOR_VIEWS )


# send test alert, with echo to terminal output

alert_view = {
        view_id: 11111111,
        alert_issue: 'SAMPLE (TEST) ALERT -- high number of tickets in past hour',
        compare: 'gte',
        threshold: 200,
        to: 'admin@example.com', 
        fresh: true,
        value: 300,
        alerted: false,
}
puts "Sample alert (also sent to #{alert_view[:to]} )\n"
puts "-----------------\n\n"
monitor_to_sendgrid.send_alert( alert_view )
monitor_to_term.send_alert( alert_view )
puts "-----------------\n\n"


# test reading view counts 

# puts "Views being monitored:\n #{MONITOR_VIEWS} \n\n"
ids = Set.new MONITOR_VIEWS.map { |view| Hash == view.class ? view[:view_id] : nil }
puts "Number of views being monitored: #{ids.length}\n"
data = datasource.view_counts(ids)
if ids.length == data[:view_counts].length
  puts "All view counts successfully read from Zendesk\n\n"
else
  puts "Problem reading view counts from Zendesk: #{ids.length} of #{data[:view_counts].length} read\n"
  abort
end

# test monitoring

puts "Current monitoring check (alerts to terminal)"
monitor_to_term.check_counts( MONITOR_VIEWS )

# test for a specific time
# monitor_to_sendgrid.check_counts( MONITOR_VIEWS, DateTime.new(2016,7,12,14) )  

puts "Test finished"