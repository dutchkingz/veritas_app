# -------------------------------------------------------
# Controls who can do what to User records.
# Only admins can manage users.
# -------------------------------------------------------
class UserPolicy < ApplicationPolicy
  # Only admins can see the full user list
  def index?
    user.admin?
  end

  # Admins can view any user; regular users can only view themselves
  def show?
    user.admin? || record == user
  end

  # Only admins can change roles and update other users
  def update?
    user.admin?
  end

  def edit?
    update?
  end

  def toggle_admin?
    user.admin?
  end

  # Only admin can destroy users
  def destroy?
    user.admin?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin?
        scope.all # Admins see all users
      else
        scope.where(id: user.id) # Regular users see only themselves
      end
    end
  end
end
