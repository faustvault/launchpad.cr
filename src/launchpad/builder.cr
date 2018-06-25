require "sqlite3"

module Launchpad
  # An error that occurs when validating a provided Launchpad layout
  class LaunchpadValidationError < Exception
  end

  class LaunchpadBuilder
    @conn : DB::Database

    def initialize(@launchpad_db_path : String,
                   @widget_layout = [] of Page,
                   @app_layout = [] of Page)
      # Widgets or apps that were not in the layout but found in the db
      @extra_widgets = [] of Item
      @extra_apps = [] of Item

      # Connect to the Launchpad SQLite database
      @conn = DB.open("sqlite3://#{@launchpad_db_path}")
    end

    # Obtain a mapping between app titles and their ids.
    #
    # :param table: The table to obtain a mapping for (should be apps, widgets or
    #               downloading_apps)
    #
    # :return: A tuple with two items.  The first value is a hash containing a mapping between
    #          the title and (id, uuid, flags) for each item.  The second item contains the
    #          maximum id of the items found.
    private def get_title_id_mapping(table : String)
      mapping = {} of String => {Int32, String, Int32}
      max_id = 0

      sql = <<-SQL
            SELECT #{table}.item_id, #{table}.title, items.uuid, items.flags
            FROM #{table}
            JOIN items ON items.rowid = #{table}.item_id
            SQL

      @conn.query(sql) do |rs|
        rs.each do
          id, title, uuid, flags = rs.read(Int32), rs.read(String), rs.read(String), rs.read(Int32)

          # Add the item to our mapping
          mapping[title] = {id, uuid, flags}

          # Obtain the maximum id in this table
          max_id = [max_id, id].max
        end
      end

      {mapping, max_id}
    end

    # Validates the provided layout to confirm that all items exist and that folders are
    # correctly structured.
    #
    # :param type_: The type of item being validated (usually Types::APP or Types::WIDGET)
    # :param layout: The layout requested by the user provided as a list (pages) of lists (items)
    #                whereby items are strings.  If the item is a folder, then it is to be a hash
    #                with a folder_title and folder_items key and associated values.
    # :param mapping: The title to data mapping for the respective items being validated.
    #
    # :raises: A LaunchpadValidationError is raised with a suitable message if an issue is found
    private def validate_layout(type_, layout, mapping)
      # Iterate through pages
      layout.each do |page|
        # Iterate through items
        page.each do |item|
          # A folder has been encountered
          if item.is_a?(Folder)
            # Verify that folder information was provided correctly
            unless item.has_key?("folder_title") && item.has_key?("folder_layout")
              raise LaunchpadValidationError.new(
                "Each folder layout must contain a folder_title and folder_layout"
              )
            end

            folder_layout = item["folder_layout"]

            # Iterate through folder pages
            folder_layout.each_with_index do |folder_page, folder_page_ordering|
              # Iterate through folder items
              folder_page.each do |title|
                # Verify that the widget or app requested exists
                unless mapping.has_key?(title)
                  if type_ == Types::WIDGET
                    raise LaunchpadValidationError.new("The widget '#{title}' does not exist")
                  elsif type_ == Types::APP
                    raise LaunchpadValidationError.new("The app '#{title}' does not exist")
                  end
                end
              end
            end
          # Flat items
          else
            title = item

            # Verify that the widget or app requested exists
            unless mapping.has_key?(title)
              if type_ == Types::WIDGET
                raise LaunchpadValidationError.new("The widget '#{title}' does not exist")
              elsif type_ == Types::APP
                raise LaunchpadValidationError.new("The app '#{title}' does not exist")
              end
            end
          end
        end
      end
    end

    # Adds additional pages to the layout containing all items that the user forgot to specify
    # in the provided layout.
    #
    # :param layout: The layout of items.
    # :param mapping: The mapping of the respective items (as obtained by get_mapping).
    private def add_extra_items(layout, mapping)
      items_in_layout = [] of Item?

      # Iterate through each page of the layout and obtain a list of items contained
      layout.each do |page|
        # Items on a page
        page.each do |item|
          # Folders
          if item.is_a?(Folder)
            folder_layout = item["folder_layout"]

            folder_layout.each do |folder_page|
              folder_page.each do |title|
                items_in_layout << title
              end
            end
          # Regular items
          else
            title = item
            items_in_layout << title
          end
        end
      end

      # Determine which items are extra items are present compared to the layout provided
      extra_items = Set.new(mapping.keys) - items_in_layout

      # If extra items are found, add them to the layout
      unless extra_items.empty?
        extra_items.each_slice(30).each do |extra_items_slice|
          layout << extra_items_slice.map { |i| i.as(PageItem) }
        end
      end

      extra_items.to_a
    end

    # Manipulates the appropriate database table to layout the items as requested by the user.
    #
    # :param type_: The type of item being manipulated (usually Types::APP or Types::WIDGET)
    # :param layout: The layout requested by the user provided as a list (pages) of lists (items)
    #                whereby items are strings.  If the item is a folder, then it is to be a hash
    #                with a folder_title and folder_items key and associated values.
    # :param mapping: The title to data mapping for the respective items being setup.
    # :param group_id: The group id to continue from when adding groups.
    # :param root_parent_id: The root parent id to add child items to.
    #
    # :return: The resultant group id after additions to continue working from.
    private def setup_items(type_, layout, mapping, group_id, root_parent_id)
      # Iterate through pages
      layout.each_with_index do |page, page_ordering|
        # Start a new page (note that the ordering starts at 1 instead of 0 as there is a
        # holding page at an ordering of 0)
        group_id += 1

        sql = <<-SQL
              INSERT INTO items
              (rowid, uuid, flags, type, parent_id, ordering)
              VALUES
              (?, ?, 2, ?, ?, ?)
              SQL
        @conn.exec(sql, group_id, Launchpad.generate_uuid, Types::PAGE, root_parent_id, page_ordering + 1)

        sql = <<-SQL
              INSERT INTO groups
              (item_id, category_id, title)
              VALUES
              (?, null, null)
              SQL
        @conn.exec(sql, group_id)

        # Capture the group id of the page to be used for child items
        page_parent_id = group_id

        # Iterate through items
        item_ordering = 0
        page.each do |item|
          # A folder has been encountered
          if item.is_a?(Folder)
            folder_title = item["folder_title"]
            folder_layout = item["folder_layout"]

            # Start a new folder
            group_id += 1

            sql = <<-SQL
                  INSERT INTO items
                  (rowid, uuid, flags, type, parent_id, ordering)
                  VALUES
                  (?, ?, 0, ?, ?, ?)
                  SQL
            @conn.exec(sql, group_id, Launchpad.generate_uuid, Types::FOLDER_ROOT, page_parent_id,
                       item_ordering)

            sql = <<-SQL
                  INSERT INTO groups
                  (item_id, category_id, title)
                  VALUES
                  (?, null, ?)
                  SQL
            @conn.exec(sql, group_id, folder_title)

            item_ordering += 1

            # Capture the group id of the folder root to be used for child items
            folder_root_parent_id = group_id

            # Iterate through folder pages
            folder_layout.each_with_index do |folder_page, folder_page_ordering|
              # Start a new folder page
              group_id += 1

              sql = <<-SQL
                    INSERT INTO items
                    (rowid, uuid, flags, type, parent_id, ordering)
                    VALUES
                    (?, ?, 2, ?, ?, ?)
                    SQL
              @conn.exec(sql, group_id, Launchpad.generate_uuid, Types::PAGE, folder_root_parent_id,
                         folder_page_ordering)

              sql = <<-SQL
                    INSERT INTO groups
                    (item_id, category_id, title)
                    VALUES
                    (?, null, null)
                    SQL
              @conn.exec(sql, group_id)

              # Iterate through folder items
              folder_item_ordering = 0

              folder_page.each do |title|
                item_id, uuid, flags = mapping[title]

                sql = <<-SQL
                      UPDATE items
                      SET uuid = ?,
                        flags = ?,
                        type = ?,
                        parent_id = ?,
                        ordering = ?
                      WHERE rowid = ?
                      SQL
                @conn.exec(sql, uuid, flags, type_, group_id, folder_item_ordering, item_id)

                folder_item_ordering += 1
              end
            end

          # Flat items
          else
            title = item
            item_id, uuid, flags = mapping[title]

            sql = <<-SQL
                  UPDATE items
                  SET uuid = ?,
                      flags = ?,
                      type = ?,
                      parent_id = ?,
                      ordering = ?
                  WHERE rowid = ?
                  SQL
            @conn.exec(sql, uuid, flags, type_, page_parent_id, item_ordering, item_id)

            item_ordering += 1
          end
        end
      end

      group_id
    end

    # Builds the requested layout for both the Launchpad apps and Dashboard widgets by updating
    # the user's Launchpad SQlite database.
    def build
      # Obtain app and widget mappings
      widget_mapping, widget_max_id = get_title_id_mapping("widgets")
      app_mapping, app_max_id = get_title_id_mapping("apps")

      # Validate widget layout
      validate_layout(Types::WIDGET, @widget_layout, widget_mapping)

      # Validate app layout
      validate_layout(Types::APP, @app_layout, app_mapping)

      # We will begin our group records using the max ids found (groups always appear after
      # apps and widgets)
      group_id = [app_max_id, widget_max_id].max

      # Add any extra widgets not found in the user's layout to the end of the layout
      @extra_widgets = add_extra_items(@widget_layout, widget_mapping)

      # Add any extra apps not found in the user's layout to the end of the layout
      @extra_apps = add_extra_items(@app_layout, app_mapping)

      # Clear all items related to groups so we can re-create them
      sql = <<-SQL
            DELETE FROM items
            WHERE type IN (?, ?, ?)
            SQL
      @conn.exec(sql, Types::ROOT, Types::FOLDER_ROOT, Types::PAGE)

      # Disable triggers on the items table temporarily so that we may create the rows with our
      # required ordering (including items which have an ordering of 0)
      sql = <<-SQL
            UPDATE dbinfo
            SET value = 1
            WHERE key = 'ignore_items_update_triggers'
            SQL
      @conn.exec(sql)

      # Add root and holding pages to items and groups
      [
        # Root for Launchpad apps
        {1, "ROOTPAGE", Types::ROOT, 0},
        {2, "HOLDINGPAGE", Types::PAGE, 1},

        # Root for dashboard widgets
        {3, "ROOTPAGE_DB", Types::ROOT, 0},
        {4, "HOLDINGPAGE_DB", Types::PAGE, 3},

        # Root for Launchpad version
        {5, "ROOTPAGE_VERS", Types::ROOT, 0},
        {6, "HOLDINGPAGE_VERS", Types::PAGE, 5}
      ].each do |rowid, uuid, type_, parent_id|
        sql = <<-SQL
              INSERT INTO items
              (rowid, uuid, flags, type, parent_id, ordering)
              VALUES (?, ?, null, ?, ?, 0)
              SQL
        @conn.exec(sql, rowid, uuid, type_, parent_id)

        sql = <<-SQL
              INSERT INTO groups
              (item_id, category_id, title)
              VALUES
              (?, null, null)
              SQL
        @conn.exec(sql, rowid)
      end

      # Setup the widgets
      group_id = setup_items(Types::WIDGET, @widget_layout, widget_mapping, group_id,
                             root_parent_id: 3)

      # Setup the apps
      group_id = setup_items(Types::APP, @app_layout, app_mapping, group_id, root_parent_id: 1)

      # Enable triggers on the items again so ordering is auto-generated
      sql = <<-SQL
            UPDATE dbinfo
            SET value = 0
            WHERE key = 'ignore_items_update_triggers'
            SQL
      @conn.exec(sql)
    end
  end
end
