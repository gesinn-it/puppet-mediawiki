Puppet::Type.type(:mediawiki_extension_composer).provide(:mediawiki_extension_composer) do
  
  desc = "Manage MediaWiki Extensions via Composer"

  commands :composer  => "composer"

  def doc_root
    resource[:doc_root]
  end
  
  def name
    resource[:name]
  end
  
  def source
    resource[:source]
  end
  
  def source_version
    resource[:source_version]
  end
  
  def instance
    resource[:instance]
  end

  def exists?
    File.exists?("#{doc_root}/extensions/#{name}/#{name}.php")
  end


  def create
    composer('require', $source, $source_version)
  end

  def destroy
    composer('remove', $source)
  end
end
