#
# Reimbursement for a given request
#
class Reimbursement < ActiveRecord::Base
  include TravelSupportProgram::HasState
  # The associated request
  belongs_to :request, :inverse_of => :reimbursement
  # The expenses of the associated request, total_amount and authorized_amount
  # will be updated during reimbursement process
  has_many :expenses, :through => :request, :autosave => false
  has_many :attachments, :class_name => "ReimbursementAttachment", :inverse_of => :reimbursement
  # Final notes are comments that users can add as feedback to a finished reimbursement
  has_many :final_notes, :as => :machine

  delegate :event, :to => :request, :prefix => false

  accepts_nested_attributes_for :request, :update_only => true,
    :allow_destroy => false, :reject_if => :reject_request

  accepts_nested_attributes_for :attachments, :allow_destroy => true

  attr_accessible :description, :requester_notes, :tsp_notes, :administrative_notes,
    :request_attributes, :attachments_attributes

  validates :request, :presence => true
  validates_associated :expenses

  audit(:create, :update, :destroy) {|m,u,a| "#{a} performed on Reimbursement by #{u.try(:nickname)}"}

  # Synchronizes user_id and request_id
  before_validation :set_user_id

  #
  state_machine :state, :initial => :incomplete do |machine|
    before_transition :set_state_updated_at

    event :submit do
      transition :incomplete => :tsp_pending
    end

    event :approve do
      transition :tsp_pending => :tsp_approved
    end

    event :authorize do
      transition :tsp_approved => :finished
    end

    event :roll_back do
      transition :tsp_pending => :incomplete
      transition :tsp_approved => :tsp_pending
    end

    event :cancel do
      transition :incomplete => :canceled
      transition :tsp_pending => :canceled
    end
  end

  # @see HasState.assign_state
  assign_state :tsp_pending, :to => :tsp
  assign_state :tsp_approved, :to => :administrative

  # @see Request#expenses_sum
  def expenses_sum(*args)
    request.expenses_sum(*args)
  end

  # Checks whether the requester should be allowed to do changes.
  #
  # @return [Boolean] true if allowed
  def editable_by_requester?
    state == 'incomplete'
  end

  # Checks whether a tsp user should be allowed to do changes.
  #
  # @return [Boolean] true if allowed
  def editable_by_tsp?
    state == 'tsp_pending'
  end

  # Checks whether the reimbursement can have final notes
  #
  # @return [Boolean] true if all conditions are met
  def can_have_final_notes?
    in_final_state?
  end


  protected

  # Used internally to synchronize request_id and user_id
  def set_user_id
    self.user_id = request.user_id
  end

  # Used internally by accepts_nested_attributes to ensure that only
  # total_amount and authorized_amount are accessible through the reimbursement
  #
  # _delete keys are also rejected, so expenses cannot either be deleted
  #
  # @return [Boolean] true if the request should be rejected
  def reject_request(attrs)
    acceptable_request_attrs = %w(id expenses_attributes)
    acceptable_expenses_attrs = %w(id total_amount authorized_amount)
    return true unless (attrs.keys - acceptable_request_attrs).empty?
    if expenses = attrs['expenses_attributes']
      expenses.values.each do |expense|
        return true unless (expense.keys - acceptable_expenses_attrs).empty?
      end
    end
    false
  end
end
