require 'activerecord/uuid'

class Conversation < ActiveRecord::Base
  include ActiveRecord::UUID

  STATUS_ARCHIVED = 'archived'
  STATUS_OPEN = 'open'

  # Internal: Regex to extract account slug and conversation number from
  # Conversation#mailbox addresses.
  MAILBOX_REGEX = Regexp.new(
                    /^(?<slug>(\w|-)+)(\+\S+)?\+(?<number>\d+)?@.+$/
                  ).freeze

  belongs_to :account
  has_many :messages,
    :after_add => :new_message,
    :dependent => :destroy

  sequential column: :number, scope: :account_id

  validates :account, presence: true

  default_scope -> { order(:updated_at => :asc) }

  scope :open, -> { where.not(status: STATUS_ARCHIVED) }
  scope :archived, -> { where(status: STATUS_ARCHIVED) }

  def ordered_messages
    messages.order(:created_at => :asc)
  end

  def participants
    messages.collect(&:person).uniq
  end

  def archived?
    status == STATUS_ARCHIVED
  end

  def archive
    update_attribute(:status, STATUS_ARCHIVED)
  end

  def un_archive
    update_attribute(:status, STATUS_OPEN)
  end

  def archive=(flag)
    if flag
      archive
    else
      un_archive
    end
  end

  def new_message(message)
    update_attribute(:status, STATUS_OPEN)
    if messages.count == 1
      ConversationMailer.new_conversation(id, message.person.id).deliver
    else
      (participants - [message.person]).each do |person|
        ConversationMailer.new_reply(id, person.id).deliver
      end
    end
  end

  # Public: Conversation specific email address for incoming email replies.
  #
  # Returns the Mail::Address customers should send email replies to.
  def mailbox
    Mail::Address.new([
      account.slug,
      "+#{number}",
      '@',
      Supportly.incoming_email_domain
    ].join.to_s)
  end

  # Public: Given an email address try to match to a conversation.
  #
  # Returns a Conversation or nil.
  def self.match_mailbox(email)
    address = Mail::Address.new(email).address

    match = MAILBOX_REGEX.match(address)
    if match
      account = Account.where(slug: match[:slug]).first
      return Conversation.where(account: account, number: match[:number]).first
    else
      return nil
    end
  end

  # Public: Given an email address try to match to a conversation or raise
  # ActiveRecord::RecordNotFound.
  #
  # Returns a Conversation or raises ActiveRecord::RecordNotFound.
  def self.match_mailbox!(email)
    self.match_mailbox(email) || raise(ActiveRecord::RecordNotFound)
  end

  def to_param
    number.to_param
  end
end
