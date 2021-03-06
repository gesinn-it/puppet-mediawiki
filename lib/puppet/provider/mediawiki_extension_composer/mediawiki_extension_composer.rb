Puppet::Type.type(:mediawiki_extension_composer).provide(:mediawiki_extension_composer) do
  
  desc = "Manage MediaWiki Extensions via Composer"

  commands :php => "php"

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
    exec({"COMPOSER_HOME" => "/usr/local/bin"}, "cd #{doc_root}/#{instance} && /usr/local/bin/composer require --prefer-dist #{source} #{source_version}")
    # update database
    php("#{doc_root}/#{instance}/maintenance/update.php", '--conf', "#{doc_root}/#{instance}/LocalSettings.php") 
  end

  def destroy
    composer('remove', $source)
  end
end
