module Launchpad
  struct Types
    ROOT = 1
    FOLDER_ROOT = 2
    PAGE = 3
    APP = 4
    DOWNLOADING_APP = 5
    WIDGET = 6
  end

  alias Item = String
  alias Folder = NamedTuple(folder_title: String, folder_layout: Array(Array(Item)))
  alias FolderOptional = NamedTuple(folder_title: String?, folder_layout: Array(Array(Item?)))
end
