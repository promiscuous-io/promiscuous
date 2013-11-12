class Moped::BSON::ObjectId
  # No {"$oid": "123"}, it's horrible.
  # TODO Document this shit.
  def to_json(*args)
    "\"#{to_s}\""
  end
end
