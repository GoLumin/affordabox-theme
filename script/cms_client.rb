# frozen_string_literal: true

# The CMS's HTTP API for the scripts in this folder, with the credentials of
# a cms CLI profile (CMS_PROFILE, from ~/.config/cms/<profile>.env).
require "json"
require "net/http"
require "uri"
require "fileutils"
require "securerandom"

module CmsClient
  PROFILE = ENV.fetch("CMS_PROFILE", "default")
  PROFILE_ENV = File.expand_path("~/.config/cms/#{PROFILE}.env")
  CONFIG = File.exist?(PROFILE_ENV) ? File.read(PROFILE_ENV).scan(/^(?:export\s+)?(\w+)="?([^"\n]*)"?$/).to_h : {}
  URL = (ENV["CMS_URL"] || CONFIG["CMS_URL"] || abort("No CMS_URL: set CMS_PROFILE to a cms CLI profile")).chomp("/")
  TOKEN = ENV["USER_AGENT_TOKEN"] || CONFIG["USER_AGENT_TOKEN"] || abort("No token in #{PROFILE_ENV}")

  module_function

  def request(method, url, body: nil, headers: {}, multipart: nil)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 30, read_timeout: 600) do |http|
      req = Net::HTTP.const_get(method.to_s.capitalize).new(uri, headers)
      if multipart
        boundary = "----affordabox#{SecureRandom.hex(12)}"
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        req.body = multipart_body(multipart, boundary)
      elsif body
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end
      http.request(req)
    end
  end

  def multipart_body(parts, boundary)
    parts.map do |name, value|
      if value.is_a?(Hash)
        "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"; filename=\"#{value[:filename].delete('"')}\"\r\n" \
          "Content-Type: #{value[:type]}\r\n\r\n".b + value[:data].b + "\r\n".b
      else
        "--#{boundary}\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n".b
      end
    end.join.b + "--#{boundary}--\r\n".b
  end

  # A call to /api<path>: the parsed answer, nil for a 404 when missing_ok.
  def call(method, path, body = nil, missing_ok: false, multipart: nil)
    res = request(method, "#{URL}/api#{path}", body:, multipart:, headers: {"Authorization" => "Bearer #{TOKEN}", "Accept" => "application/json"})
    code = res.code.to_i
    return nil if missing_ok && code == 404
    abort "#{method.upcase} #{path} answered #{code}: #{res.body.to_s[0, 800]}" unless code.between?(200, 299)
    warn "  #{path} is waiting for approval (Approvals plugin)" if code == 202
    res.body.to_s.strip.empty? ? {} : JSON.parse(res.body)
  end

  # Updates the record at `path`, or creates it at `create_path`.
  def upsert(path, wrapper, attributes, create_path:)
    if call(:get, path, missing_ok: true)
      call(:patch, path, {wrapper => attributes})
    else
      call(:post, create_path, {wrapper => attributes})
    end
  end

  def upload(filename, type, data, alt: nil, folder: "/affordabox")
    parts = {"file" => {filename:, type:, data:}, "folder" => folder}
    parts["alt"] = alt if alt
    record = call(:post, "/assets", multipart: parts)
    (record["asset"] || record)["id"].to_s
  end

  TYPES = {".svg" => "image/svg+xml", ".png" => "image/png", ".webp" => "image/webp", ".jpg" => "image/jpeg",
           ".jpeg" => "image/jpeg", ".mp4" => "video/mp4"}.freeze

  def content_type(path) = TYPES.fetch(File.extname(path).downcase)
end
