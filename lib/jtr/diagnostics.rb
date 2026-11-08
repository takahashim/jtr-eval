# frozen_string_literal: true

module Jtr
  # 形態素解析器に依存しない決定論的な診断指標。
  # 総合スコアには使わず、モデルごとの癖を可視化する診断レポート用。
  module Diagnostics
    SENTENCE_END = /(?<=[。！？!?])\s*/
    KANJI = /\p{Han}/
    KATAKANA = /[\p{Katakana}ー]/
    LATIN = /[A-Za-z]/
    DESU_MASU = /(です|ます|ません|でした|ましょう|ください)[。！？!?]?\s*\z/
    DEARU = /(である|だ|であった|だった|する|した|ない|ている|られる)[。！？!?]?\s*\z/
    FULLWIDTH_PUNCT = /[、。]/
    HALFWIDTH_PUNCT = /(?<=[\p{Hiragana}\p{Katakana}\p{Han}])[,.](?=\s|\z)/

    # 冗長表現・翻訳調のマーカー。件数を数えるだけ。
    REDUNDANT_PATTERNS = {
      "することができ" => /することができ/,
      "を行う/を行い" => /を行(う|い|っ)/,
      "という(こと|もの)" => /という(こと|もの)/,
      "基本的に" => /基本的に/,
      "〜的には" => /的には/,
      "可能です" => /が可能です/,
      "非常に/とても" => /(非常に|とても)/
    }.freeze

    PREAMBLE_PATTERNS = [
      /\A(以下|それでは|はい|承知|了解|もちろん)/,
      /について(説明|解説|ご説明)(します|いたします|していきます)/
    ].freeze

    BOILERPLATE_CLOSING = [
      /以上(が|で|です)/,
      /参考になれば/,
      /ご不明な点/,
      /何か(ご)?質問/,
      /お役に立て/
    ].freeze

    Result = Struct.new(
      :chars, :chars_prose, :code_block_chars, :code_blocks,
      :sentences, :mean_sentence_len, :max_sentence_len, :long_sentence_ratio,
      :max_commas, :mean_commas,
      :kanji_ratio, :katakana_ratio, :latin_ratio,
      :style_mix, :desu_masu_sentences, :dearu_sentences,
      :bullet_lines, :bullet_ratio, :headings, :max_bullet_depth,
      :punct_mixed, :redundant, :preamble, :boilerplate_closing,
      keyword_init: true
    ) do
      def to_h = super.transform_values { |v| v.is_a?(Float) ? v.round(3) : v }
    end

    module_function

    def analyze(text)
      text = text.to_s.gsub("\r\n", "\n")
      code_blocks = text.scan(/```.*?```/m)
      prose = text.gsub(/```.*?```/m, "\n").gsub(/`[^`\n]*`/, "")

      lines = prose.lines.map(&:chomp)
      bullet_lines = lines.select { |l| l =~ /\A\s*([-*+]|\d+[.)])\s+/ }
      non_empty = lines.reject { |l| l.strip.empty? }
      headings = lines.count { |l| l =~ /\A#{"#"}{1,6}\s/ }
      max_depth = bullet_lines.map { |l| l[/\A\s*/].size / 2 }.max || 0

      # 見出し・箇条書き記号を落としてから文に分割する。
      body = non_empty.map { |l| l.sub(/\A\s*#+\s*/, "").sub(/\A\s*([-*+]|\d+[.)])\s+/, "") }.join("\n")
      sentences = body.split(SENTENCE_END).map(&:strip).reject(&:empty?)
      lens = sentences.map { |s| s.gsub(/\s/, "").size }
      commas = sentences.map { |s| s.count("、") }

      desu = sentences.count { |s| s =~ DESU_MASU }
      dearu = sentences.count { |s| s =~ DEARU && s !~ DESU_MASU }

      chars_prose = prose.gsub(/\s/, "").size
      denom = [chars_prose, 1].max

      first_line = non_empty.first.to_s
      last_lines = non_empty.last(2).join

      Result.new(
        chars: text.gsub(/\s/, "").size,
        chars_prose: chars_prose,
        code_block_chars: code_blocks.sum(&:size),
        code_blocks: code_blocks.size,
        sentences: sentences.size,
        mean_sentence_len: mean(lens),
        max_sentence_len: lens.max || 0,
        long_sentence_ratio: ratio(lens.count { |n| n > 80 }, lens.size),
        max_commas: commas.max || 0,
        mean_commas: mean(commas),
        kanji_ratio: prose.scan(KANJI).size.fdiv(denom),
        katakana_ratio: prose.scan(KATAKANA).size.fdiv(denom),
        latin_ratio: prose.scan(LATIN).size.fdiv(denom),
        style_mix: desu.positive? && dearu.positive?,
        desu_masu_sentences: desu,
        dearu_sentences: dearu,
        bullet_lines: bullet_lines.size,
        bullet_ratio: ratio(bullet_lines.size, non_empty.size),
        headings: headings,
        max_bullet_depth: max_depth,
        punct_mixed: prose.match?(FULLWIDTH_PUNCT) && prose.match?(HALFWIDTH_PUNCT),
        redundant: REDUNDANT_PATTERNS.transform_values { |re| prose.scan(re).size }.reject { |_, n| n.zero? },
        preamble: PREAMBLE_PATTERNS.any? { |re| first_line.match?(re) },
        boilerplate_closing: BOILERPLATE_CLOSING.any? { |re| last_lines.match?(re) }
      )
    end

    def mean(arr) = arr.empty? ? 0.0 : arr.sum.fdiv(arr.size)
    def ratio(n, d) = d.zero? ? 0.0 : n.fdiv(d)
  end
end
