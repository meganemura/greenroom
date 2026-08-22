# frozen_string_literal: true

require "test_helper"

class Greenroom::DigestTest < Minitest::Test
  def test_of_returns_a_64_character_sha256_hex_digest
    digest = Greenroom::Digest.of("hello")

    assert_equal 64, digest.length
    assert_match(/\A[0-9a-f]{64}\z/, digest)
  end

  def test_of_returns_nil_for_nil
    assert_nil Greenroom::Digest.of(nil)
  end

  def test_of_is_stable_for_equal_values
    assert_equal Greenroom::Digest.of([1, "a", :b]), Greenroom::Digest.of([1, "a", :b])
  end

  def test_of_differs_for_different_values
    refute_equal Greenroom::Digest.of("a"), Greenroom::Digest.of("b")
  end

  def test_of_is_built_from_inspect_so_string_and_symbol_do_not_collide
    # If `of` hashed `to_s` instead of `inspect`, "a" and :a would produce the
    # same digest, since both stringify to "a". Distinct types must digest
    # differently so a mismatch between a String control and a Symbol
    # candidate is never hidden by the digest step itself.
    refute_equal Greenroom::Digest.of("a"), Greenroom::Digest.of(:a)
  end
end
