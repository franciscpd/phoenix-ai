defmodule PhoenixAI.Guardrails.JailbreakDetector.Default do
  @moduledoc """
  Default keyword-based jailbreak detector.

  Scores messages against pattern categories using case-insensitive word-boundary
  regex matching. Also attempts base64 decoding for encoding evasion detection.

  ## Categories and weights

  - `:role_override` — 0.3 — patterns that attempt to redefine the AI's persona
  - `:instruction_override` — 0.4 — patterns that attempt to override instructions
  - `:dan_patterns` — 0.3 — well-known jailbreak technique patterns

  ## Scoring

  Each matched category contributes its weight once (multiple matches within the
  same category do not stack). Scores are summed and capped at 1.0.

  Base64-decoded content that matches keyword patterns adds an additional 0.2 for
  the `:encoding_evasion` category.
  """

  @behaviour PhoenixAI.Guardrails.JailbreakDetector

  alias PhoenixAI.Guardrails.JailbreakDetector.DetectionResult

  @keyword_categories [
    {:role_override, 0.3,
     [
       ~r/\byou are now\b/i,
       ~r/\bpretend to be\b/i,
       ~r/\bact as\b/i,
       ~r/\byou are an?\b/i,
       ~r/\bfrom now on you\b/i,
       ~r/\byour new persona\b/i
     ]},
    {:instruction_override, 0.4,
     [
       ~r/\bignore previous\b/i,
       ~r/\bforget your instructions\b/i,
       ~r/\bdisregard (all |your )?(previous |prior )?instructions\b/i,
       ~r/\boverride (your )?(previous )?instructions\b/i,
       ~r/\bignore (all |your )?(previous |prior )?instructions\b/i,
       ~r/\byour (previous |prior )?instructions (are |were )?(now )?(void|invalid|cancelled)\b/i
     ]},
    {:dan_patterns, 0.3,
     [
       ~r/\bDAN\b/,
       ~r/\bjailbreak\b/i,
       ~r/\bdo anything now\b/i,
       ~r/\bno restrictions?\b/i,
       ~r/\bunrestricted mode\b/i,
       ~r/\bgrandma (exploit|trick|hack)\b/i
     ]}
  ]

  @encoding_evasion_weight 0.2

  @impl true
  def detect(content, _opts) do
    {keyword_score, keyword_patterns, keyword_categories} = scan_keyword_categories(content)
    {evasion_score, evasion_patterns, evasion_categories} = scan_base64(content)

    total_score = min(1.0, keyword_score + evasion_score)
    all_patterns = keyword_patterns ++ evasion_patterns
    all_categories = keyword_categories ++ evasion_categories

    result = %DetectionResult{
      score: total_score,
      patterns: all_patterns,
      details: %{categories: all_categories}
    }

    if total_score > 0.0 do
      {:detected, result}
    else
      {:safe, result}
    end
  end

  # Scans content against all keyword categories.
  # Each category contributes its weight at most once.
  defp scan_keyword_categories(content) do
    Enum.reduce(@keyword_categories, {0.0, [], []}, fn {category, weight, regexes}, acc ->
      matched = Enum.flat_map(regexes, &match_regex(&1, content))
      accumulate_category(acc, category, weight, matched)
    end)
  end

  defp match_regex(regex, content) do
    case Regex.scan(regex, content) do
      [] -> []
      _ -> [clean_pattern_source(regex)]
    end
  end

  defp accumulate_category({score, patterns, cats}, category, weight, matched)
       when matched != [] do
    {score + weight, patterns ++ matched, cats ++ [category]}
  end

  defp accumulate_category(acc, _category, _weight, _matched), do: acc

  # Finds base64 strings (20+ chars), decodes them, and re-scans with keyword patterns.
  defp scan_base64(content) do
    base64_regex = ~r/[A-Za-z0-9+\/]{20,}={0,2}/

    matches = Regex.scan(base64_regex, content) |> List.flatten()

    found =
      Enum.any?(matches, fn candidate ->
        case Base.decode64(candidate) do
          {:ok, decoded} ->
            {score, _patterns, _cats} = scan_keyword_categories(decoded)
            score > 0.0

          :error ->
            false
        end
      end)

    if found do
      {@encoding_evasion_weight, ["base64_encoded_payload"], [:encoding_evasion]}
    else
      {0.0, [], []}
    end
  end

  # Strips \b anchors from regex source for human-readable pattern names.
  defp clean_pattern_source(regex) do
    regex
    |> Regex.source()
    |> String.replace("\\b", "")
    |> String.trim()
  end
end
