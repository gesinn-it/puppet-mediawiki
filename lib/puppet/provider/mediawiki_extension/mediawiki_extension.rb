Puppet::Type.type(:mediawiki_extension).provide(:mediawiki_extension) do
  
  desc = "Manage Media Wiki Extensions"

  commands :tar  => "tar"
  commands :rm   => "rm"
  commands :curl => "curl"
  commands :php  => "php"

#  confine :osfamily => :RedHat
#  defaultfor :operatingsystem => [:CentOS, :RedHat]

  def doc_root
    resource[:doc_root]
  end
  
  def name
    resource[:name]
  end
  
  def source
    resource[:source]
  end

  def strip_components
    resource[:strip_components]
  end
  
  def instance
    resource[:instance]
  end

  def exists?
    File.exists?("#{doc_root}/extensions/#{name}/#{name}.php")
  end


  def create
    # Fetch code to tmp using caching
    # -L: follow redirects
    # -R: make curl attempt to figure out the timestamp of the remote file, and if that is available make the local file get that same timestamp. 
    # -z: Request a file that has been modified later than the given time and date of an existing file
    curl('-L', '-R', '-z', "/vagrant_share/tmp/#{name}.tar.gz", '-o', "/vagrant_share/tmp/#{name}.tar.gz", "#{source}")
    
    # Make deploy dir
    File.directory?("#{doc_root}/#{instance}/extensions/#{name}") or Dir.mkdir("#{doc_root}/#{instance}/extensions/#{name}", 0755)
    
    # Unpack code to Extensions dir
    tar('-xzf', "/vagrant_share/tmp/#{name}.tar.gz", "--strip-components=#{strip_components}", '-C', "#{doc_root}/#{instance}/extensions/#{name}")
    
    # sync db
    #php("#{doc_root}/#{instance}/maintenance/update.php", '--conf', "#{doc_root}/#{instance}/LocalSettings.php") 
  end

  def destroy
    rm('-rf', "#{doc_root}/extensions/#{name}")
  end
end
