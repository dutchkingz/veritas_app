require 'sendgrid-ruby'

module Sendgrid
  class InvitationEmailService
    include SendGrid

    def self.call(email)
      new(email).call
    end

    def initialize(email)
      @email = email
      @api_key = ENV['SENDGRID_API_KEY'] || Rails.application.credentials.dig(:sendgrid, :api_key)
      @from_email = ENV['SENDGRID_FROM_EMAIL'] || Rails.application.credentials.dig(:sendgrid, :from_email)
      @app_url = "https://veritas-app-314a53c53525.herokuapp.com/" # Matching existing service pattern
    end

    def call
      return false unless valid_configuration?

      mail = build_mail
      send_request(mail)
    end

    private

    def build_mail
      from    = Email.new(email: @from_email, name: 'VERITAS Intelligence')
      to      = Email.new(email: @email)
      subject = 'URGENT: Access Authorized for VERITAS Intelligence Platform'

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

                <table width="600" cellpadding="0" cellspacing="0" border="0" style="max-width:600px;width:100%;background-color:#0d0d1a;border:1px solid #00f0ff;border-radius:4px;">

                  <!-- Header Image -->
                  <tr>
                    <td>
                      <img src="https://raw.githubusercontent.com/antigravity-images/veritas/main/invitation_hero.png" alt="Veritas Intelligence" style="width:100%;height:auto;display:block;border-top-left-radius:4px;border-top-right-radius:4px;">
                    </td>
                  </tr>

                  <!-- Header Text -->
                  <tr>
                    <td style="padding:32px 40px 24px;border-bottom:1px solid #1a1a2e;text-align:center;">
                      <p style="margin:0 0 8px;font-size:11px;letter-spacing:4px;color:#00d4ff;text-transform:uppercase;">Limited Access Invitation</p>
                      <h1 style="margin:0;font-size:36px;font-weight:700;letter-spacing:6px;color:#ffffff;text-transform:uppercase;">VERITAS</h1>
                      <p style="margin:10px 0 0;font-size:12px;color:#5a6a7a;letter-spacing:2px;">GLOBAL SIGNALING LAYER</p>
                    </td>
                  </tr>

                  <!-- Status bar -->
                  <tr>
                    <td style="padding:12px 40px;background-color:#0a0a16;border-bottom:1px solid #1a1a2e;">
                      <p style="margin:0;font-size:11px;color:#00ff87;letter-spacing:2px;">
                        &#x25CF; CLEARANCE GRANTED &nbsp;&nbsp;|&nbsp;&nbsp; NODE: PENDING &nbsp;&nbsp;|&nbsp;&nbsp; REGION: GLOBAL
                      </p>
                    </td>
                  </tr>

                  <!-- Body -->
                  <tr>
                    <td style="padding:36px 40px;">
                      <p style="margin:0 0 20px;font-size:15px;line-height:1.7;color:#c8d0e0;">
                        You have been granted high-level clearance to join the <strong>Veritas Intelligence signaling network</strong>. 
                      </p>
                      <p style="margin:0 0 20px;font-size:15px;line-height:1.7;color:#c8d0e0;">
                        Our platform provides real-time narrative tracking, semantic threat analysis, and global convergence detection. Your node has been identified as a critical point for intelligence ingestion.
                      </p>
                      
                      <!-- Why Join Us -->
                      <div style="background-color:rgba(0, 212, 255, 0.05);padding:20px;border-radius:4px;margin:20px 0 32px;">
                        <p style="margin:0 0 12px;font-size:12px;color:#00d4ff;letter-spacing:2px;font-weight:bold;">SYSTEM CAPABILITIES:</p>
                        <p style="margin:0 0 8px;font-size:14px;color:#c8d0e0;">● Real-time Semantic Threat Analysis</p>
                        <p style="margin:0 0 8px;font-size:14px;color:#c8d0e0;">● Global Narrative Arc Tracking</p>
                        <p style="margin:0 0 8px;font-size:14px;color:#c8d0e0;">● Advanced War Room Visualization</p>
                        <p style="margin:0 0 0;font-size:14px;color:#c8d0e0;">● AI-Driven Convergence Detection</p>
                      </div>

                      <!-- CTA -->
                      <table cellpadding="0" cellspacing="0" border="0" width="100%">
                        <tr>
                          <td align="center">
                            <table cellpadding="0" cellspacing="0" border="0">
                              <tr>
                                <td style="background-color:transparent;border:1px solid #00d4ff;border-radius:3px;">
                                  <a href="#{@app_url}users/sign_up" style="display:inline-block;padding:14px 32px;font-size:13px;font-weight:700;letter-spacing:3px;color:#00d4ff;text-decoration:none;text-transform:uppercase;">
                                    INITIALIZE ACCESS &#x2192;
                                  </a>
                                </td>
                              </tr>
                            </table>
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
                        This message was generated automatically. All signals are monitored.
                      </p>
                      <p style="margin:0;font-size:11px;color:#2a3a4a;letter-spacing:1px;">
                        &copy; VERITAS SYSTEMS // WAR ROOM
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
          Rails.logger.info("Invitation email successfully sent to #{@email}.")
          true
        else
          Rails.logger.error("SendGrid API Error for #{@email} - Status: #{response.status_code}, Body: #{response.body}")
          false
        end
      rescue StandardError => e
        Rails.logger.error("Exception during SendGrid invitation delivery to #{@email}: #{e.message}")
        false
      end
    end

    def valid_configuration?
      if @api_key.blank? || @from_email.blank?
        Rails.logger.error("SendGrid configuration is missing for Invitations.")
        false
      else
        true
      end
    end
  end
end
