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
      from    = Email.new(email: @from_email, name: 'VERITAS Intelligence')
      to      = Email.new(email: @user.email)
      subject = 'VERITAS — Access Granted'

      username = @user.email.split('@').first

      html_content = <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
        </head>
        <body style="margin:0;padding:0;background-color:#09090f;font-family:'Courier New',Courier,monospace;color:#c8d0e0;">

          <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#09090f;">
            <tr>
              <td align="center" style="padding:40px 16px;">

                <table width="600" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%;background-color:#0d0d1a;border:1px solid #00d4ff;border-radius:4px;">

                  <!-- Header -->
                  <tr>
                    <td style="padding:32px 40px 24px;border-bottom:1px solid #1a1a2e;text-align:center;">
                      <p style="margin:0 0 8px;font-size:11px;letter-spacing:4px;color:#00d4ff;text-transform:uppercase;">Intelligence Platform</p>
                      <h1 style="margin:0;font-size:36px;font-weight:700;letter-spacing:6px;color:#ffffff;text-transform:uppercase;">VERITAS</h1>
                      <p style="margin:10px 0 0;font-size:12px;color:#5a6a7a;letter-spacing:2px;">A RADAR FOR TRUTH</p>
                    </td>
                  </tr>

                  <!-- Status bar -->
                  <tr>
                    <td style="padding:12px 40px;background-color:#0a0a16;border-bottom:1px solid #1a1a2e;">
                      <p style="margin:0;font-size:11px;color:#00ff87;letter-spacing:2px;">
                        &#x25CF; ACCESS GRANTED &nbsp;&nbsp;|&nbsp;&nbsp; CLEARANCE LEVEL: USER &nbsp;&nbsp;|&nbsp;&nbsp; STATUS: ACTIVE
                      </p>
                    </td>
                  </tr>

                  <!-- Body -->
                  <tr>
                    <td style="padding:36px 40px;">
                      <p style="margin:0 0 20px;font-size:13px;color:#5a6a7a;letter-spacing:1px;">OPERATIVE // #{username.upcase}</p>
                      <p style="margin:0 0 20px;font-size:15px;line-height:1.7;color:#c8d0e0;">
                        Your credentials have been verified. You now have access to the VERITAS intelligence platform.
                      </p>
                      <p style="margin:0 0 20px;font-size:15px;line-height:1.7;color:#c8d0e0;">
                        VERITAS tracks how narratives are engineered and amplified across global media in real time — from origin to proxy network to outlet. Not just <em>what</em> is being said, but <em>how</em> the world is being made to say it.
                      </p>
                      <p style="margin:0 0 32px;font-size:15px;line-height:1.7;color:#c8d0e0;">
                        The globe is live. The arcs are moving. The truth is in the signal.
                      </p>

                      <!-- CTA -->
                      <table cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td style="background-color:#00d4ff;border-radius:3px;">
                            <a href="https://veritas-app-314a53c53525.herokuapp.com/" style="display:inline-block;padding:14px 32px;font-size:13px;font-weight:700;letter-spacing:3px;color:#09090f;text-decoration:none;text-transform:uppercase;">
                              ENTER VERITAS &#x2192;
                            </a>
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>

                  <!-- Divider -->
                  <tr>
                    <td style="padding:0 40px;">
                      <hr style="border:none;border-top:1px solid #1a1a2e;margin:0;">
                    </td>
                  </tr>

                  <!-- Footer -->
                  <tr>
                    <td style="padding:24px 40px;text-align:center;">
                      <p style="margin:0 0 8px;font-size:11px;color:#2a3a4a;letter-spacing:1px;">
                        This message was generated automatically. Do not reply.
                      </p>
                      <p style="margin:0;font-size:11px;color:#2a3a4a;letter-spacing:1px;">
                        &copy; VERITAS Intelligence Platform
                      </p>
                    </td>
                  </tr>

                </table>

              </td>
            </tr>
          </table>

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
