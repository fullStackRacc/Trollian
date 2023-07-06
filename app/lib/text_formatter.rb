# frozen_string_literal: true

class TextFormatter
  include ActionView::Helpers::TextHelper
  include ERB::Util
  include RoutingHelper

  URL_PREFIX_REGEX = /\A(https?:\/\/(www\.)?|xmpp:)/.freeze

  DEFAULT_REL = %w(nofollow noopener noreferrer).freeze

  DEFAULT_OPTIONS = {
    multiline: true,
  }.freeze

  attr_reader :text, :options

  # @param [String] text
  # @param [Hash] options
  # @option options [Boolean] :multiline
  # @option options [Boolean] :with_domains
  # @option options [Boolean] :with_rel_me
  # @option options [Array<Account>] :preloaded_accounts
  def initialize(text, options = {})
    @text    = text
    @options = DEFAULT_OPTIONS.merge(options)
  end

  def entities
    @entities ||= Extractor.extract_entities_with_indices(text, extract_url_without_protocol: false)
  end

  def to_s
    return ''.html_safe if text.blank?

    html = rewrite do |entity|
      if entity[:url]
        link_to_url(entity)
      elsif entity[:hashtag]
        link_to_hashtag(entity)
      elsif entity[:screen_name]
        link_to_mention(entity)
      end
    end

    html = simple_format(html, {}, sanitize: false).delete("\n") if multiline?
    html = format_bbcode(html)

    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  def to_s_no_link
    return ''.html_safe if text.blank?
    html = text
    html = simple_format(html, {}, sanitize: false).delete("\n") if multiline?
    html = format_bbcode(html)

    html.html_safe # rubocop:disable Rails/OutputSafety
  end

  class << self
    include ERB::Util

    def shortened_link(url, rel_me: false)
      url = Addressable::URI.parse(url).to_s
      rel = rel_me ? (DEFAULT_REL + %w(me)) : DEFAULT_REL

      prefix      = url.match(URL_PREFIX_REGEX).to_s
      display_url = url[prefix.length, 30]
      suffix      = url[prefix.length + 30..-1]
      cutoff      = url[prefix.length..-1].length > 30

      <<~HTML.squish
        <a href="#{h(url)}" target="_blank" rel="#{rel.join(' ')}"><span class="invisible">#{h(prefix)}</span><span class="#{cutoff ? 'ellipsis' : ''}">#{h(display_url)}</span><span class="invisible">#{h(suffix)}</span></a>
      HTML
    rescue Addressable::URI::InvalidURIError, IDN::Idna::IdnaError
      h(url)
    end
  end

  private

  def rewrite
    entities.sort_by! do |entity|
      entity[:indices].first
    end

    result = ''.dup

    last_index = entities.reduce(0) do |index, entity|
      indices = entity[:indices]
      result << h(text[index...indices.first])
      result << yield(entity)
      indices.last
    end

    result << h(text[last_index..-1])

    result
  end

  def link_to_url(entity)
    TextFormatter.shortened_link(entity[:url], rel_me: with_rel_me?)
  end

  def link_to_hashtag(entity)
    hashtag = entity[:hashtag]
    url     = tag_url(hashtag)

    <<~HTML.squish
      <a href="#{h(url)}" class="mention hashtag" rel="tag">#<span>#{h(hashtag)}</span></a>
    HTML
  end

  def link_to_mention(entity)
    username, domain = entity[:screen_name].split('@')
    domain           = nil if local_domain?(domain)
    account          = nil

    if preloaded_accounts?
      same_username_hits = 0

      preloaded_accounts.each do |other_account|
        same_username = other_account.username.casecmp(username).zero?
        same_domain   = other_account.domain.nil? ? domain.nil? : other_account.domain.casecmp(domain)&.zero?

        if same_username && !same_domain
          same_username_hits += 1
        elsif same_username && same_domain
          account = other_account
        end
      end
    else
      account = entity_cache.mention(username, domain)
    end

    return "@#{h(entity[:screen_name])}" if account.nil?

    url = ActivityPub::TagManager.instance.url_for(account)
    display_username = same_username_hits&.positive? || with_domains? ? account.pretty_acct : account.username

    <<~HTML.squish
      <span class="h-card"><a href="#{h(url)}" class="u-url mention">@<span>#{h(display_username)}</span></a></span>
    HTML
  end

  def entity_cache
    @entity_cache ||= EntityCache.instance
  end

  def tag_manager
    @tag_manager ||= TagManager.instance
  end

  delegate :local_domain?, to: :tag_manager

  def multiline?
    options[:multiline]
  end

  def with_domains?
    options[:with_domains]
  end

  def with_rel_me?
    options[:with_rel_me]
  end

  def preloaded_accounts
    options[:preloaded_accounts]
  end

  def preloaded_accounts?
    preloaded_accounts.present?
  end

  def format_bbcode(html)
    begin
      allowed_bbcodes = [:i, :b, :color, :quote, :code, :size, :u, :strike, :spin, :pulse, :flip, :large, :colorhex, :hex, :quote, :code, :center, :right, :url, :caps, :lower, :kan, :comic, :doc, :hs, :yan, :oa, :sc, :impact, :luci, :pap, :copap, :na, :nac, :cute, :img, :faicon, :break, :joke, :u, :book, :bone,]
      html = html.bbcode_to_html(false, {
        :spin => {
          :html_open => '<span class="bbcode__spin">', :html_close => '</span>',
          :description => 'Make text spin',
          :example => 'This is [spin]spin[/spin].'},
        :pulse => {
          :html_open => '<span class="bbcode__pulse">', :html_close => '</span>',
          :description => 'Make text pulse',
          :example => 'This is [pulse]pulse[/pulse].'},
        :b => {
          :html_open => '<span class="bbcode__b">', :html_close => '</span>',
          :description => 'Make text bold',
          :example => 'This is [b]bold[/b].'},
        :u => {
          :html_open => '<span class="bbcode__u">', :html_close => '</span>',
          :description => 'Make text underlined',
          :example => 'This is [u]underline[/u].'},
        :i => {
          :html_open => '<span class="bbcode__i">', :html_close => '</span>',
          :description => 'Make text italic',
          :example => 'This is [i]italic[/i].'},
        :u => {
          :html_open => '<span class="bbcode__u">', :html_close => '</span>',
          :description => 'Under line',
          :example => 'This is [u]Under line[/u].'},
        :strike => {
          :html_open => '<span class="bbcode__s">', :html_close => '</span>',
          :description => 'line through',
          :example => 'This is [strike]line through[/strike].'},
        :flip => {
          :html_open => '<span class="bbcode__flip-%direction%">', :html_close => '</span>',
          :description => 'Flip text',
          :example => '[flip=horizontal]This is flip[/flip]',
          :allow_quick_param => true, :allow_between_as_param => false,
          :quick_param_format => /(horizontal|vertical)/,
          :quick_param_format_description => 'The size parameter \'%param%\' is incorrect, a number is expected',
          :param_tokens => [{:token => :direction}]},
        :large => {
          :html_open => '<span class="fa-%size%">', :html_close => '</span>',
          :description => 'Large text',
          :example => '[large=2x]Large text[/large]',
          :allow_quick_param => true, :allow_between_as_param => false,
          :quick_param_format => /(2x|3x|4x|5x)/,
          :quick_param_format_description => 'The size parameter \'%param%\' is incorrect, a number is expected',
          :param_tokens => [{:token => :size}]},
        :colorhex => {
          :html_open => '<span class="bbcode__color" data-bbcodecolor="#%colorhex%;">', :html_close => '</span>',
          :description => 'Change the color of the text',
          :example => '[colorhex=ff0000]This is red[/colorhex]',
          :allow_quick_param => true, :allow_between_as_param => false,
          :quick_param_format => /([0-9a-f]{6})/i,
          :param_tokens => [{:token => :colorhex}]},
        :hex => {
          :html_open => '<span class="bbcode__color" data-bbcodecolor="#%colorhex%;">', :html_close => '</span>',
          :description => 'Change the color of the text',
          :example => '[hex=ff0000]This is red[/hex]',
          :allow_quick_param => true, :allow_between_as_param => false,
          :quick_param_format => /([0-9a-f]{6})/i,
          :param_tokens => [{:token => :hex}]},
        :color => {
          :html_open => '<span class="bbcode__color" data-bbcodecolor="%color%">', :html_close => '</span>',
          :description => 'Use color',
          :example => '[color=red]This is red[/color]',
          :allow_quick_param => true, :allow_between_as_param => false,
          :quick_param_format => /([a-z]+)/i,
          :param_tokens => [{:token => :color}]},
        :size => {
          :html_open => '<span class="bbcode__size" data-bbcodesize="%size%px">', :html_close => '</span>',
          :description => 'Change the size of the text',
          :example => '[size=32]This is 32px[/size]',
          :allow_quick_param => true, :allow_between_as_param => false,
          :quick_param_format => /(\d+)/,
          :quick_param_format_description => 'The size parameter \'%param%\' is incorrect, a number is expected',
          :param_tokens => [{:token => :size}]},
        :url => {
          :html_open => '<a target="_blank" rel="nofollow noopener" href="%url%">%between%', :html_close => '</a>',
          :description => 'Link to another page',
          :example => '[url=http://www.google.com/]link[/url].',
          :require_between => true,
          :allow_quick_param => true, :allow_between_as_param => false,
          :quick_param_format => /^((((http|https|ftp):\/\/)).+)$/,
          :param_tokens => [{:token => :url}],
          :quick_param_format_description => 'The URL should start with http:// https://, ftp://'},
        :quote => {
          :html_open => '<div class="bbcode__quote">', :html_close => '</div>',
          :description => 'Quote',
          :example => 'This is [quote]quote[/quote].'},
        :code => {
          :html_open => '<div class="bbcode__code">', :html_close => '</div>',
          :description => 'Code',
          :example => 'This is [code]Code[/code].'},
        :center => {
          :html_open => '<div style="text-align:center;">', :html_close => '</div>',
          :description => 'Center a text',
          :example => '[center]This is centered[/center].'},
        :right => {
          :html_open => '<div style="text-align:right;">', :html_close => '</div>',
          :description => 'Right Align a text',
          :example => '[right]This is centered[/right].'},
        :caps => {
          :html_open => '<span class="bbcode__caps">', :html_close => '</span>',
          :description => 'Capitalize',
          :example => 'This is [caps]capitalize[/caps].'},
        :lower => {
          :html_open => '<span class="bbcode__lower">', :html_close => '</span>',
          :description => 'Lowercase',
          :example => 'This is [lower]lowercase[/lower].'},
        :kan => {
          :html_open => '<span class="bbcode__kan">', :html_close => '</span>',
          :description => 'uppercase',
          :example => 'This is [kan]uppercase[/kan].'},
        :comic => {
          :html_open => '<span class="bbcode__comic">', :html_close => '</span>',
          :description => 'comic sans',
          :example => 'This is [comic]comic sans[/comic].'},
        :doc => {
          :html_open => '<span class="bbcode__doc">', :html_close => '</span>',
          :description => 'transparent text',
          :example => 'This is [doc]transparent text[/doc].'},
        :hs => {
          :html_open => '<span class="bbcode__hs">', :html_close => '</span>',
          :description => 'Courier New',
          :example => 'This is [hs]Courier New[/hs].'},
        :yan => {
          :html_open => '<span class="bbcode__yan">', :html_close => '</span>',
          :description => 'CUTE',
          :example => 'This is [yan]CUTE[/yan].'},
        :oa => {
          :html_open => '<span class="bbcode__oa">', :html_close => '</span>',
          :description => 'Old Alternian',
          :example => 'This is [oa]Old Alternian[/oa].'},
        :sc => {
          :html_open => '<span class="bbcode__sc">', :html_close => '</span>',
          :description => 'Small Caps',
          :example => 'This is [sc]Small Caps[/sc].'},
        :impact => {
          :html_open => '<span class="bbcode__impact">', :html_close => '</span>',
          :description => 'Impact',
          :example => 'This is [impact]Impact[/impact].'},
        :luci => {
          :html_open => '<span class="bbcode__luci">', :html_close => '</span>',
          :description => 'Lucida Sans',
          :example => 'This is [luci]Lucida Sans[/luci].'},
        :pap => {
          :html_open => '<span class="bbcode__pap">', :html_close => '</span>',
          :description => 'Papyrus',
          :example => 'This is [pap]Papyrus[/pap].'},
        :copap => {
          :html_open => '<span class="bbcode__copap">', :html_close => '</span>',
          :description => 'Comic Papyrus',
          :example => 'This is [copap]Comic Papyrus[/copap].'},
        :na => {
          :html_open => '<span class="bbcode__na">', :html_close => '</span>',
          :description => 'New Alternian',
          :example => 'This is [na]New Alternian[/na].'},
        :nac => {
          :html_open => '<span class="bbcode__nac">', :html_close => '</span>',
          :description => 'New Alternian Console',
          :example => 'This is [nac]New Alternian Console[/nac].'},
        :cute => {
          :html_open => '<span class="bbcode__cute">', :html_close => '</span>',
          :description => 'Cute',
          :example => 'This is [cute]Cute[/cute].'},
        :img => {
          :html_open => '<img src="%between%" %width%%height%alt="" />', :html_close => '',
          :description => 'Image',
          :example => '[img]http://www.google.com/intl/en_ALL/images/logo.gif[/img].',
          :only_allow => [],
          :require_between => true,
          :allow_quick_param => true, 
          :allow_between_as_param => false,
          :quick_param_format => /^(\d+)x(\d+)$/,
          :param_tokens => [{ :token => :width, :prefix => 'width="', :postfix => '" ', :optional => true },
                                { :token => :height,  :prefix => 'height="', :postfix => '" ', :optional => true } ],
          :quick_param_format_description => 'The image parameters \'%param%\' are incorrect, \'<width>x<height>\' excepted'},
        :faicon => {
          :html_open => '<span class="fa fa-%between% bbcode__faicon" style="display: none"></span><span class="faicon_FTL">%between%</span>', :html_close => '',
          :description => 'Use Font Awesome Icons',
          :example => '[faicon]users[/faicon]',
          :only_allow => [],
          :require_between => true},
         :break => {
          :html_open => '<br />', :html_close => '',
          :description => 'Insert a line break',
          :example => 'This is [break]bold[/break]'},
        :joke => {
          :html_open => '<span class="bbcode__joke">', :html_close => '</span>',
          :description => 'Joke',
          :example => 'This is [joke]Joke[/joke].'},
        :book => {
          :html_open => '<span class="bbcode__book">', :html_close => '</span>',
          :description => 'Book',
          :example => 'This is [book]Book[/book].'},
        :bone => {
          :html_open => '<span class="bbcode__bone">', :html_close => '</span>',
          :description => 'Bone',
          :example => 'This is [bone]Bones[/bone].'},
      }, :enable, *allowed_bbcodes)
    rescue Exception => e
    end
    html
  end         
end

