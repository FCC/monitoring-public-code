# operational monitor chron job
# run one-off test_monitor to check set-up before scheduling this job

require_relative 'zendesk_read'
require_relative 'mailers'
require_relative 'monitor_counts'
require_relative 'monitor_configuration'

include MonitorConfiguration

datasource = ZendeskRead.new( DATASOURCE_CONFIG )
mailer = ViaSendGrid.new( SENDGRID_CONFIG )

runner = MonitorCounts.new( datasource, mailer, MONITOR_CONFIG )

runner.check_counts( MONITOR_VIEWS )
