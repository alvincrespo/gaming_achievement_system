class Guildship < ApplicationRecord
  belongs_to :guild

  enum :guild_type, {
    casual: 0,
    competitive: 1,
    esports: 2,
    streaming: 3,
    social: 4
  }
end
