# frozen_string_literal: true

require "test_helper"
require "greenroom/census/middleware"

class Greenroom::Census::MiddlewareTest < Minitest::Test
  include Greenroom::ResetsGlobalState

  def test_call_yields_and_uninstalls_the_recorder
    Greenroom::Recorder.install(Greenroom::Recorder.new(run_id: "r1"))
    middleware = Greenroom::Census::Middleware.new
    yielded = false

    middleware.call(nil, nil, nil) { yielded = true }

    assert yielded
    assert_nil Greenroom::Recorder.current
  end

  def test_call_uninstalls_the_recorder_even_if_the_block_raises
    # `each_iteration` raising skips `Census::Job#on_stop` (Sidekiq re-raises
    # out of `perform` without calling it), which would otherwise leave the
    # thread-local recorder installed. Sidekiq reuses worker threads, so the
    # very next, unrelated job Sidekiq runs on this thread would otherwise
    # find an experiment already turned on. This middleware is the backstop
    # for that leak.
    Greenroom::Recorder.install(Greenroom::Recorder.new(run_id: "r1"))
    middleware = Greenroom::Census::Middleware.new

    assert_raises(RuntimeError) do
      middleware.call(nil, nil, nil) { raise "boom" }
    end

    assert_nil Greenroom::Recorder.current
  end

  def test_call_is_harmless_when_no_recorder_was_installed
    middleware = Greenroom::Census::Middleware.new

    result = middleware.call(nil, nil, nil) { :ok }

    assert_equal :ok, result
    assert_nil Greenroom::Recorder.current
  end
end
