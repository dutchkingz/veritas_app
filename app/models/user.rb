class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  ROLES = %w[visitor user admin].freeze

  validates :role, inclusion: { in: ROLES }

  def admin?
    role == "admin"
  end

  after_create_commit :send_welcome_email

  private

  def send_welcome_email
    WelcomeEmailJob.perform_later(self.id)
  end
end
