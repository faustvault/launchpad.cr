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

  alias FolderPage = Array(Item)
  alias Folder = NamedTuple(folder_title: String, folder_layout: Array(FolderPage))

  alias PageItem = Item | Folder
  alias Page = Array(PageItem)

  alias FolderPageOptional = Array(Item?)
  alias FolderOptional = NamedTuple(folder_title: String?, folder_layout: Array(FolderPageOptional))

  alias PageItemOptional = Item? | FolderOptional
  alias PageOptional = Array(PageItemOptional)
end
