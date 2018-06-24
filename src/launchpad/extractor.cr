module Launchpad
  # TODO
  alias Thingo = {Int32, Int32?, String?, String?, String?}

  # Builds a data structure containing the layout for a particular type of data.
  #
  # :param root: The root id of the tree being built.
  # :param parent_mapping: The mapping between parent_ids and items.
  #
  # :returns: The layout data structure that was built as a tuple where the first item is the
  #           widget layout and the second item is the app layout.
  private def self.build_layout(root, parent_mapping)
    layout = [] of Array(App? | Widget? | FolderOptional)

    # Iterate through pages
    parent_mapping[root].each do |page_id, _, _, _, _|
      page_items = [] of (App? | Widget? | FolderOptional)

      # Iterate through items
      parent_mapping[page_id].each do |id, type_, app_title, widget_title, group_title|
        # An app has been encountered which is added to the page
        if type_ == Types::APP
          page_items << app_title

        # A widget has been encountered which is added to the page
        elsif type_ == Types::WIDGET
          page_items << widget_title

        # A folder has been encountered
        elsif type_ == Types::FOLDER_ROOT
          # Start a hash for the folder with its title and layout
          folder = FolderOptional.new(folder_title: group_title, folder_layout: [] of Array(App? | Widget?))

          # Iterate through folder pages
          parent_mapping[id].each do |folder_page_id, _, _, _, _|
            folder_page_items = [] of String?

            # Iterate through folder items
            parent_mapping[folder_page_id].each do |folder_item_id, folder_item_type,
                                                    folder_item_app_title, folder_widget_title,
                                                    folder_group_title|
              # An app has been encountered which is being added to the folder page
              if folder_item_type == Types::APP
                folder_page_items << folder_item_app_title

              # A widget has been encountered which is being added to the folder page
              elsif folder_item_type == Types::WIDGET
                folder_page_items << folder_widget_title
              end
            end

            # Add the page to the folder
            folder["folder_layout"] << folder_page_items
          end

          # Add the folder item to the page
          page_items << folder
        end
      end

      # Add the page to the layout
      layout << page_items
    end

    return layout
  end

  def self.extract(launchpad_db_path)
    # Connect to the Launchpad SQLite database
    DB.open("sqlite3://#{launchpad_db_path}") do |conn|
      # Iterate through root elements for Launchpad apps and Dashboard widgets
      sql = <<-SQL
            SELECT key, value
            FROM dbinfo
            WHERE key IN ('launchpad_root', 'dashboard_root');
            SQL

      dashboard_root : Int32? = nil
      launchpad_root : Int32? = nil

      conn.query(sql) do |rs|
        rs.each do
          key, value = rs.read(String), rs.read(String)
          if key == "launchpad_root"
            launchpad_root = value.to_i32
          elsif key == "dashboard_root"
            dashboard_root = value.to_i32
          end
        end
      end

      # Build a mapping between the parent_id and the associated items
      parent_mapping = Hash(Int32, Array(Thingo)).new do |hash, key|
        hash[key] = [] of Thingo
      end

      # Obtain all items and their associated titles
      sql = <<-SQL
            SELECT items.rowid, items.parent_id, items.type,
                   apps.title AS app_title,
                   widgets.title AS widget_title,
                   groups.title AS group_title
            FROM items
            LEFT JOIN apps ON apps.item_id = items.rowid
            LEFT JOIN widgets ON widgets.item_id = items.rowid
            LEFT JOIN groups ON groups.item_id = items.rowid
            WHERE items.uuid NOT IN ('ROOTPAGE', 'HOLDINGPAGE',
                                     'ROOTPAGE_DB', 'HOLDINGPAGE_DB',
                                     'ROOTPAGE_VERS', 'HOLDINGPAGE_VERS')
            ORDER BY items.parent_id, items.ordering
            SQL

      conn.query(sql) do |rs|
        rs.each do
          id, parent_id, type_ = rs.read(Int32), rs.read(Int32), rs.read(Int32?)
          app_title, widget_title, group_title = rs.read(String?), rs.read(String?), rs.read(String?)
          parent_mapping[parent_id] << {id, type_, app_title, widget_title, group_title}
        end
      end

      widget_layout = build_layout(dashboard_root, parent_mapping)
      app_layout = build_layout(launchpad_root, parent_mapping)

      {widget_layout, app_layout}
    end
  end
end
