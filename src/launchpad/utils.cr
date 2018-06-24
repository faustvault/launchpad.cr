module Launchpad
  # Generate a UUID using uuidgen
  def self.generate_uuid
    Process.run("uuidgen") do |process|
      process.output.gets_to_end.chomp
    end
  end

  # Determines the user's Launchpad database directory containing the SQLite database.
  def self.get_launchpad_db_dir
    Process.run("getconf", args: ["DARWIN_USER_DIR"]) do |process|
      darwin_user_dir = process.output.gets_to_end.chomp
      File.join(darwin_user_dir, "com.apple.dock.launchpad", "db")
    end
  end
end
