module MonitorConfiguration

# Monitoring view array

# ** required keys in a monitoring view configuration
# view_id: Zendesk view id that's the basis for the alert
# alert_issue: text used in subject and body of emailed alert
# freq: frequency of view monitoring; hourly, daily, weekly, hour-n {every n hours}, day-n {every n days}
# compare: gte {greater than or equal to}, lte {less than or equal to}
# threshold: ticket count for gte or lte test
# to: array of email address to receive alert

# ** optional keys in a monitoring view configuration
# days_wk: days of week on which check runs (array of numbers from 0 = Sunday to 7 = Saturday)
# hours_day: hours of day on which check runs (array of numbers from 0 to 23)
# holidays: dates on which check does not run ( array of dates specified as strings like '2016-04-12' )
# offset: hours offset for first event of day (freq: daily, offset: 20 ==> alert at 5pm EST)
# type: event (default) or report (send email with counts in view at every monitoring time)

# example monitoring configuration below; change to serve your specific needs

  TO_ADDRESSES_1 = [          # email addresses for particular view; for re-use in MONITOR_VIEWS
  'admin@example.com',
  'manager@example.com',
  ]

  TO_ADDRESSES_2 = [         
    'watcherA@example.com',
  ]
  

  TO_ADDRESSES_3 = [         
    'watcherB@example.com',
    'watcherC@example.com',  
  ]

  MONITOR_VIEWS = [
    {view_id: 11111111,
      alert_issue: 'notably high number of tickets via web in past hour',
      freq: 'hourly',
      compare: 'gte',
      threshold: 500,
      to: TO_ADDRESSES_1},
    {view_id: 22222222,
      alert_issue: 'no tickets received via web in past two hours',
      freq: 'hour-2',
      compare: 'lte',
      threshold: 0, 
      to: TO_ADDRESSES_1},
    {view_id: 22222222,
      alert_issue: 'notably high number of tickets via web in past two hours',
      freq: 'hour-2',
      compare: 'gte',
      threshold: 1000, 
      to: TO_ADDRESSES_1},
    {view_id: 33333333,
      alert_issue: 'low number of tickets via web in past day (excluding weekends)',
      freq: 'daily',  
      days_wk: (1..5).to_a,
      compare: 'lte',
      threshold: 500,  
      offset: 21,    # run test at 5pm EST
      to: TO_ADDRESSES_1},
    {view_id: 33333333,
      alert_issue: 'high number of tickets via web in past day',
      freq: 'daily',
      compare: 'gte',
      threshold: 3000, 
      to: TO_ADDRESSES_1},
    {view_id: 33333333,
      alert_issue: 'number of tickets via web in past day',
      freq: 'daily',
      type: 'report',
      days_wk: (1..5).to_a,      
      offset: 10, 
      to: TO_ADDRESSES_1},    
    {view_id: 44444444,
      alert_issue: 'notably low number of tickets via web in past week',
      freq: 'weekly',
      compare: 'lte',
      threshold: 1500, 
      to: TO_ADDRESSES_1},
    {view_id: 44444444,
      alert_issue: 'notably high number of tickets via web in past week',
      freq: 'weekly',
      compare: 'gte',
      threshold: 10000, 
      to: TO_ADDRESSES_1},
    {view_id: 55555555,
      alert_issue: 'type X tickets in past week',
      freq: 'weekly',
      type: 'report',
      days_wk: [2],      
      offset: 14, 
      to: TO_ADDRESSES_3},       
    ]
  
# mailer-specific configuration
# api key either in env setting SENDGRID_API_KEY (best) or in file specified for config hash key key_location
  SENDGRID_CONFIG = {
    from: 'admin@example.com',
  }

# Zendesk datasource instance, with read agent
# api key either in env setting ZD_KEY (best) or in file specified for config hash key key_location
  DATASOURCE_CONFIG = {
    zendesk_url: 'https://XXXX.zendesk.com',
    agent_email: 'agent@example.com',
  }
  
# Monitoring method configuration
  MONITOR_CONFIG = {
    admin_email: ['admin@example.com', 'manager@example.com'],  # notify addresses for technical problems
    zendesk_url: DATASOURCE_CONFIG[:zendesk_url], #used for specifying view link in alert
    sleep_time: 1, # in minutes
    api_tries: 3, # repeat calls necessary if view counted returned as stale
    event_subject_prefix: 'ZD-event: ', # alert email subject prefix
    event_body_heading: "** Event monitoring for XXXX Zendesk ticket system **\n\n",
    report_subject_prefix: 'ZD-report: ',
    report_body_heading: "** Report on XXXX Zendesk tickets **\n\n",
  }

end