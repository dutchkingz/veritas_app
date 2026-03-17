class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :saved_articles, dependent: :destroy
  has_many :briefings, dependent: :destroy
  has_one  :model_config, class_name: "UserModelConfig", dependent: :destroy

  # Returns existing config or a new unsaved instance with defaults
  def effective_model_config
    model_config || build_model_config
  end

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
