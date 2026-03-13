module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      # Globe data is public — unauthenticated users can still receive broadcasts.
      # current_user will be nil for guests, a User record for logged-in visitors.
      self.current_user = env["warden"].user
    end
  end
end
