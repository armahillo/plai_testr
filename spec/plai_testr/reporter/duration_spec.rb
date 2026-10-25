require 'spec_helper'

RSpec.describe PlaiTestr::Reporter::Duration do
  it 'shows minutes and seconds under an hour' do
    expect(described_class.format(0.4)).to eq('0m 00s')
    expect(described_class.format(125.6)).to eq('2m 06s')
  end

  it 'shows hours and minutes from an hour on' do
    expect(described_class.format(3 * 3600 + 7 * 60 + 59)).to eq('3h 07m')
  end
end
