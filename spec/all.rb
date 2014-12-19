require 'docker'
require 'pry'

build_path = File.expand_path File.join(File.dirname(__FILE__), '..')
image_tag = 'klevo/percona'
IMAGE = Docker::Image.build_from_dir build_path, t: image_tag

describe "image" do
  it "should expose the mysql tcp port" do
    expect(IMAGE.json["Config"]["ExposedPorts"]).to include("3306/tcp")
  end
end

describe "running a container without attached volumes" do
  before :all do
    @container = Docker::Container.create(
      'Image' => image_tag, 
      'Detach' => true, 
      'Env' => [ 'MYSQL_ROOT_PASSWORD=something' ],
      # 'Volumes' => {
      #   ''
      # }
    )
    @container.start
    # Wait for mysql to start
    @container.exec(['bash', '-c', 'mysqladmin --silent --wait=30 ping'])
  end

  it "has root .my.cnf file that contains the password specified on container create" do
    root_my_cnf = @container.exec(['bash', '-c', 'cat /root/.my.cnf']).first.first
    expect(root_my_cnf).to match(/password=something/)
  end
  
  it "runs mysql daemon" do
    stdout, stderr = @container.exec(['bash', '-c', 'ps aux'])
    expect(stdout.first).to match(/\/usr\/sbin\/mysqld/)
  end
  
  it "can run mysql query through build in mysql client" do
    stdout, stderr = @container.exec(['bash', '-c', 'mysql -e "show databases;"'])
    expect(stderr.first).to_not match(/Access denied for user/)
    
    expect(stdout.first).to match(/mysql/)
    expect(stdout.first).to match(/information_schema/)
    expect(stdout.first).to_not match(/test/)
  end

  after :all do
    @container.delete(force: true)
  end
end

# Note: we're using a mounted volume located within the host vm, because if we would mount something from OS X, we would have write permission problems: https://github.com/boot2docker/boot2docker/issues/581
describe "running a container with mounted volume" do
  before :all do
    `boot2docker ssh "if [ -d /tmp/empty-data-dir ]; then sudo rm -rf /tmp/empty-data-dir; fi; mkdir /tmp/empty-data-dir"`
    
    @container = Docker::Container.create(
      'Name' => 'test_db1_master', # used later for replication tests
      'Image' => image_tag, 
      'Detach' => true, 
      'Env' => [ 'MYSQL_ROOT_PASSWORD=foo' ]
    )
    @container.start('Binds' => '/tmp/empty-data-dir:/var/lib/mysql')
    # Wait for mysql to start
    @container.exec(['bash', '-c', 'mysqladmin --silent --wait=30 ping'])
  end
  
  it "can run mysql query through build in mysql client" do
    stdout, stderr = @container.exec(['bash', '-c', 'mysql -e "show databases;"'])
    expect(stderr.first).to_not match(/Access denied for user/)
    
    expect(stdout.first).to match(/mysql/)
    expect(stdout.first).to match(/information_schema/)
    expect(stdout.first).to_not match(/test/)
    expect(stdout.first).to_not match(/survive/)
  end
  
  # the following also tests the case where we mount an already existing data dir
  it "can be stopped, started again and data survives" do
    @container.exec(['bash', '-c', 'mysql -e "create database survive;"'])
    @container.restart
    # Wait for mysql to start
    @container.exec(['bash', '-c', 'mysqladmin --silent --wait=30 ping'])
    stdout, stderr = @container.exec(['bash', '-c', 'mysql -e "show databases;"'])
    expect(stdout.first).to match(/survive/)
  end
  
  it "can be run as replication slave" do
    @master = @container # just for clarity and intent
    
    # 1. Spin up a new container, that is going to be our replication slave
    @slave = Docker::Container.create(
      'Image' => image_tag, 
      'Detach' => true, 
      'Env' => [ 
        'MYSQL_ROOT_PASSWORD=foo',
        'REPLICATION_SLAVE_MASTER_HOST=test_db1_master',
        'REPLICATION_SLAVE_REMOTE_PORT=3306',
        'REPLICATION_SLAVE_USER=db1_slave',
        'REPLICATION_SLAVE_PASSWORD=slaveUserPass'
      ]
    )
    @slave.start
    # Wait for slave to start
    @slave.exec(['bash', '-c', 'mysqladmin --silent --wait=30 ping'])
    
    # 2. Use the replication_master_sql script to prepare master for replication
    stdout, stderr = @slave.exec(['bash', '-c', 'replication_master_sql'])
    
    sql = stdout.first.chomp.strip
    # puts "Executing on master: \"#{sql}\""
    @master.exec(['bash', '-c', %{mysql -e "#{sql}"}])
    
    # 3. Do some changes on the master
    
    
    # 3. Check whether the query has propagated to the slave
    
    # Cleanup
    @slave.delete(force: true)
  end
  
  after :all do
    @container.delete(force: true)
    `boot2docker ssh "sudo rm -rf /tmp/empty-data-dir"`
  end
end
