class AchievementUnlock < ApplicationRecord
  belongs_to :player
  belongs_to :achievement
  belongs_to :guild

  scope :active, -> { where(deleted_at: nil) }
  scope :completed, -> { where(progress_percentage: 100) }

  def completed?
    progress_percentage == 100
  end
end
