Puppet::Type.newtype(:mediawiki_extension) do
    @doc = "Manage Media Wiki Extensions"

    ensurable

    newparam(:name) do
       desc "The name of the extension to be managed"

       isnamevar
    end

    newparam(:source) do
      desc "The location of the Extension to be loaded."
    end
    
    newparam(:strip_components) do
      desc "strip NUMBER leading components from file names on extraction"
    end    
 
    newparam(:instance) do
      desc "MediaWiki puppet instance identifier."
    end
 
    newparam(:doc_root) do
      desc "MediaWiki base installation path."
    end

end
