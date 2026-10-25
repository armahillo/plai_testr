require 'spec_helper'

RSpec.describe PlaiTestr::Reporter::Tables do
  it 'pads every column of a table to its widest cell' do
    markdown = "## Result\n\n| Player | Score |\n|---|---:|\n| Moon Shooter (Player 4) | 23 |\n| P2 | 101 |\n\nDone.\n"

    expect(described_class.align(markdown)).to eq(<<~MD)
      ## Result

      | Player                  | Score |
      | ----------------------- | ----: |
      | Moon Shooter (Player 4) | 23    |
      | P2                      | 101   |

      Done.
    MD
  end

  it 'keeps escaped pipes inside a cell and fills short rows' do
    expect(described_class.align("| a | b |\n|---|---|\n| x \\| y |\n")).to eq("| a      | b   |\n| ------ | --- |\n| x \\| y |     |\n")
  end

  it 'leaves tables inside code fences alone' do
    markdown = "```\n| a | b |\n|---|---|\n```\n"

    expect(described_class.align(markdown)).to eq(markdown)
  end
end
