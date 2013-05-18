require "curb"
require "nokogiri"
require "json"
require 'digest/sha1'
require "tmpdir"

class Gfrom

  attr_accessor :form, :fields

  MATCHERS = '//input[@type="text"] | //input[@type="radio"] |//input[@type="checkbox"] | //input[@type="hidden"] | //textarea | //form'

  def initialize(url, regenerate_cache = false)
    @form = Hash.new
    @fields = []

    cache = "#{Dir.tmpdir}/#{Digest::SHA1.hexdigest(url)}"
    File.delete cache if regenerate_cache

    unless File.exists?(cache)
      req = Curl.get(url)
      File.open(cache, "w") do |f|
        f.write req.body_str
      end
    end

    keys = []

    doc = Nokogiri::XML(File.open(cache))
    doc.search(MATCHERS).each do |node|
      case node.name
      when "form"
        @form[:action] = node.attributes["action"].value unless @form.has_key?(:action)
        @form[:title] = doc.search('//title').first.text.strip unless @form.has_key?(:title)
      else
        n = hash_it(node)
        @fields << n
        keys << n[:name]
      end
    end
    @form[:keys] = keys

  end

  def submit(params)
    response = Curl.post(@form[:action], params)
    doc = Nokogiri::XML.parse(response.body_str)
    errorheader = doc.search('//div[@class="errorheader"]')
    success = errorheader.empty?
    success_response = doc.search('//div[@class="ss-custom-resp"]').first.text.strip
    out = { :success => success, :message => success_response || doc.search('//title').first.text.strip }
    unless success
      out[:message] = errorheader.children.first.text.strip
    end
    out
  end

  private

  def hash_it(node)
    group = ["checkbox", "radio"]
    object = Hash.new
    object[:element] = node.name
    node.attributes.each do |k,v|
      if (k == "name" and v.value == "checkbox" and node.search("//input[@name=\"#{v.value}\"]").length > 1)
        # checkbox needs name to be array'ed
        object[k.to_sym] = "#{v.value}[]"
      else
        object[k.to_sym] = v.value
      end
      if k == "id"
        label = node.search("//label[@for=\"#{v.value}\"]").first
        if label
          object[:label] = label.children.first.text.strip
          object[:required] = true unless label.search("//label[@for=\"#{v.value}\"]/span[contains(@class, \"required\")]").empty?
        end
      end
      if object[:label].nil? and group.include?(object[:type])
        object[:label] = node.attributes["value"].value
      end
    end
    object
  end

end