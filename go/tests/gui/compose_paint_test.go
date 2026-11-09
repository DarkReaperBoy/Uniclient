package tests

import (
	"testing"

	"uniclient/ui/history"
	"uniclient/ui/material"

	. "uniclient/ui/app"
	"uniclient/ui/history/render"
)

func TestPaintComposeBarRecordsWithoutPanic(t *testing.T) {
	p := render.NewChatPainter()
	gtx := renderContext()
	sch := material.SchemeFor(material.Light)
	m := composeModel(t, 400, 600)
	m.ChatCompose.Placeholder = "Message"
	m, _ = Update(m, ChatComposeTyped{Text: "a\nb\nc\nd\ne\nf\ng\nh\ni\nj", Now: 1000})
	p.PaintComposeBar(gtx, m.ComposePane(), sch)
	m, _ = Update(m, ChatComposeCursorKey{Dir: ComposeLeft, Select: true})
	p.PaintComposeBar(gtx, m.ComposePane(), sch)
	hidden, _ := Update(InitialModel(), Resized{Width: 400, Height: 600})
	p.PaintComposeBar(gtx, hidden.ComposePane(), sch)
	p.PaintComposeBar(gtx, history.ComposePaneView{}, sch)
}
