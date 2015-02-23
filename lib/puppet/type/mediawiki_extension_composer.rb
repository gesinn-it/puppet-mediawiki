Puppet::Type.newtype(:mediawiki_extension_composer) do
    @doc = "Manage MediaWiki Extensions via Composer"

    ensurable

    newparam(:name) do
       desc "The name of the extension to be managed"

       isnamevar
    end

    newparam(:source) do
      desc "The location of the Extension to be loaded."
    end
    
    newparam(:source_version) do
      desc "The version of the Extension to be loaded."
    end
 
    newparam(:instance) do
      desc "MediaWiki puppet instance identifier."
    end
 
    newparam(:doc_root) do
      desc "MediaWiki base installation path."
    end

end
