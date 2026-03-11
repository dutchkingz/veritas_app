require 'sendgrid-ruby'

module Sendgrid
  class WelcomeEmailService
    include SendGrid

    def self.call(user)
      new(user).call
    end

    def initialize(user)
      @user = user
      @api_key = ENV['SENDGRID_API_KEY'] || Rails.application.credentials.dig(:sendgrid, :api_key)
      @from_email = ENV['SENDGRID_FROM_EMAIL'] || Rails.application.credentials.dig(:sendgrid, :from_email)
    end

    def call
      return false unless valid_configuration?

      mail = build_mail
      send_request(mail)
    end

    private

    def build_mail
      from = Email.new(email: @from_email, name: 'Our App Team')
      to = Email.new(email: @user.email)
      subject = 'Welcome to Our App!'
      
      html_content = <<~HTML
        <html>
          <body>
            <h1>Welcome aboard!</h1>
            <p>Hi #{@user.email.split('@').first}, we are thrilled to have you here.</p>
          </body>
        </html>
      HTML

      content = Content.new(type: 'text/html', value: html_content)
      
      Mail.new(from, subject, to, content)
    end

    def send_request(mail)
      sg_client = SendGrid::API.new(api_key: @api_key)
      
      begin
        response = sg_client.client.mail._('send').post(request_body: mail.to_json)
        
        if response.status_code.to_s.start_with?('2')
          Rails.logger.info("Welcome email successfully sent to #{@user.email}.")
          true
        else
          Rails.logger.error("SendGrid API Error for #{@user.email} - Status: #{response.status_code}, Body: #{response.body}")
          false
        end
      rescue StandardError => e
        Rails.logger.error("Exception during SendGrid delivery to #{@user.email}: #{e.message}")
        false
      end
    end

    def valid_configuration?
      if @api_key.blank? || @from_email.blank?
        Rails.logger.error("SendGrid configuration is missing. API Key or From Email is blank.")
        false
      else
        true
      end
    end
  end
end
