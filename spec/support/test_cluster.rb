#taken from: https://github.com/bsm/promiscuous_cluster/blob/09241015f293bc6056e45af523dd2dce43643d21/scenario/scenario.rb

require 'fileutils'
require 'pathname'

class TestCluster
  ROOT    = Pathname.new(File.expand_path("../../../", __FILE__))
  VERSION = "0.8.1.1"
  SERVER  = ROOT.join "kafka_2.10-#{VERSION}"
  TOPIC   = 'test'

  KAFKA_PORT  = 29092
  KAFKA_BIN   = SERVER.join("bin", "kafka-server-start.sh")
  KAFKA_CFG   = SERVER.join("config", "server-promiscuous.properties")
  KAFKA_TMP   = "tmp/kafka-logs"
  KAFKA_TOPIC = SERVER.join("bin", "kafka-topics.sh")

  ZOOKP_PORT = 22181
  ZOOKP_BIN  = SERVER.join("bin", "zookeeper-server-start.sh")
  ZOOKP_CFG  = SERVER.join("config", "zookeeper-promiscuous.properties")
  ZOOKP_TMP  = "tmp/zookeeper"

  LOG4J_CFG  = SERVER.join("config", "log4j.properties")

  def initialize
    @pids = {}

    configure

    [KAFKA_BIN, ZOOKP_BIN, KAFKA_CFG, ZOOKP_CFG].each do |path|
      abort "Unable to locate #{path}. File does not exist!" unless path.file?
    end

    Signal.trap("INT") { stop }
  end

  def start
    FileUtils.rm_rf KAFKA_TMP.to_s
    FileUtils.rm_rf ZOOKP_TMP.to_s

    spawn KAFKA_BIN, KAFKA_CFG
    spawn ZOOKP_BIN, ZOOKP_CFG
    sleep(10)

    create_test_topic
  end

  def stop
    @pids.each do |_, pid|
      Process.kill :TERM, pid
    end
  end

  def configure
    download

    KAFKA_CFG.open("w") do |f|
      f.write SERVER.join("config", "server.properties").read.
        sub("=9092", "=#{KAFKA_PORT}").
        sub(":2181", ":#{ZOOKP_PORT}").
        sub("num.partitions=2", "num.partitions=1").
        sub("#log.flush.interval.ms=1000", "log.flush.interval.ms=10").
        sub("/tmp/kafka-logs", KAFKA_TMP)
    end
    ZOOKP_CFG.open("w") do |f|
      f.write SERVER.join("config", "zookeeper.properties").read.
        sub("/tmp/zookeeper", ZOOKP_TMP).
        sub("=2181", "=#{ZOOKP_PORT}")
    end
    content = LOG4J_CFG.read
    LOG4J_CFG.open("w") do |f|
      f.write content.gsub("INFO", "FATAL")
    end if content.include?("INFO")
  end

  def create_test_topic
    sh "#{KAFKA_TOPIC} --zookeeper localhost:#{ZOOKP_PORT} --create --topic #{TOPIC} --partitions 1 --replication-factor 1"
  end

  def download
    return if SERVER.directory?
    puts "Downloading Kafka #{VERSION} to #{ROOT}..."
    sh "cd #{ROOT} && curl http://www.mirrorservice.org/sites/ftp.apache.org/kafka/#{VERSION}/kafka_2.10-#{VERSION}.tgz | tar xz"
  end

  def abort(message)
    Kernel.abort "ERROR: #{message}"
  end

  def sh(*bits)
    cmd = bits.join(" ")
    system(cmd) || abort(cmd)
  end

  def spawn(*args)
    cmd = args.join(" ")
    @pids[cmd] = Process.spawn(cmd)
  end
end
