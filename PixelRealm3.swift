// PIXEL REALM v2, part 3 of 5: the hand-drawn pictures kept as text, creatures and their kinds, vehicles, the game state, the player and input,
// the app itself, and the Mod Creator+ screens (with the sprite editor, the sun and moon editor and the tree designer).
// The game is five files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm5.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 3 (a01_artsheet).

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// ===== a01_artsheet =====

// MARK: - The hand-drawn pictures, kept as text
// Creatures and blocks are drawn at 16 pixels to a block with the tools in tools/art (parts laid over
// each other, a dark line round each), and packed here as text: pictures in a string cost the build far
// less than the same pictures as code. A picture's pixels run row after row, repeats written as a
// count: "12.3ab" is twelve clear pixels, three of colour a and one of colour b.

enum ArtSheet {
	/// A creature starts on a line "name|width|height|row of the soles|column of the middle|colours|
	/// poses"; the lines after it that start with "+" hold its frames, one after another with "/" between
	static let creatureText: String = """
		// <art:creatures> written by tools/art/build.py pack from tools/art/creatures: change the drawings, not this
		archer|34|34|31|13.5|a17191E,b574736,c392F24,d93B6A4,e71A09D,f3A5357,g507272,h1A1418,iD87067,j381E26,kE7E2C9,l7F8B66,m5A6641,nE4DCCD,o9A7A54,p3E4833,q2C342B,r72573B,s677186,t3F4C5F,u2C3544,v212633,w494048,x3A3238,y2A242C,z1E1A20|idle:0;walk:1,2,3,4;windup:5;strike:5;shoot:5
		+14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2ga22.a3l5f2a22.a2lm5fanoa20.a2lmf2lf2manaoa19.al2mf2mfmp
		+an2aoa18.a3mfmp3fan2aoa18.ap2mfmp2edfn2aoa18.a2p2mfq2gefn2ara19.a2p2m4fana2ra19.qpqmpmqa.an2ara18.a3qp3qa.an2aoa18.asqt2quq2.an2aoa18.a6vuv2an2aoa18.as2tuv2uv2anaoa19.as2
		+tuv2uv2anoa21.a2tuv2uva.2a22.a2tuv2uva25.at2uvu2va25.aeg2agfa26.aeg2agfa25.a4wv3xa24.a4wyv2xza24.4av4a50./14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2h
		+ih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2ga22.a3l5f2a22.a2lm5fanoa20.a2lmf2lf2manaoa19.al2mf2mfmpan2aoa18.a3mfmp3fan2aoa18.ap2mfmp2edfn2aoa18.a2p2mfq2gefn2ara19.
		+a2p2m4fana2ra19.qpqmpmqa.an2ara18.a3qp3qa.an2aoa18.asqt2quq2.an2aoa18.a6vuv2an2aoa18.a2s2tuvuv2anaoa20.as2tu2va.anoa22.a2t2uva2.2a23.vs2tuv28.av2tua28.avega29.aveg2a28.av
		+4wa27.av3wya28.a3va52./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2ga22.a3l5f2a22.a2lm5fanoa20.a2lmf
		+2lf2manaoa19.al2mf2mfmpan2aoa18.a3mfmp3fan2aoa18.ap2mfmp2edfn2aoa18.a2p2mfq2gefn2ara19.a2p2m4fana2ra19.qpqmpmqa.an2ara18.a3qp3qa.an2aoa18.vsqt2quqv2an2aoa18.a6vuv2an2aoa1
		+8.as2tuvtuv2anaoa20.a2tuvt2uvanoa21.a2tu2a2uv3a22.at2u2agfva24.aega.agfa25.aeg2a3xa24.a4wv3xza23.a4wyv3a25.5a54./14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.
		+acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2ga22.a3l5f2a22.a2lm5fanoa20.a2lmf2lf2manaoa19.al2mf2mfmpan2aoa18.a3mfmp3fan2aoa18.ap2mfmp2edfn2aoa18.a2p2mfq2gefn
		+2ara19.a2p2m4fana2ra19.qpqmpmqa.an2ara18.a3qp3qa.an2aoa18.asqt2quq2.an2aoa18.a6vuv2an2aoa18.as2tuvt2uvanaoa18.as2tu2at2uvanoa19.a2t2ua.a2u2v2a19.as2tua2.at2uva20.a2tua4.a
		+2uva20.aega5.agfa21.aega5.agf2a20.a3wa4.a4xa19.a3wya3.a3xza20.4a5.4a48./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2g
		+e5ja23.2a2fgkjk2ga22.a3l5f2a22.a2lm5fanoa20.a2lmf2lf2manaoa19.al2mf2mfmpan2aoa18.a3mfmp3fan2aoa18.ap2mfmp2edfn2aoa18.a2p2mfq2gefn2ara19.a2p2m4fana2ra19.qpqmpmqa.an2ara18.
		+a3qp3qa.an2aoa18.vsqt2quqv2an2aoa18.a6vuv2an2aoa18.a2stuv2uv2anaoa20.as2tuvuv2anoa22.a2tuvuva.2a23.aegu3va26.aegvgfa26.a3wvgfa26.a3wyv2xa26.2a2v3xza28.5a50./14.5a28.a5b2a
		+25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja3.a20.a2ge5ja2.aoa18.2a2fgkjk2ga.anaoa16.a3l6fa.an2aoa15.a2l2m5f2a3f2aoa14.a2l2mf4lmfe3defr
		+a14.al2maf4m2p5egfa14.a4mf3pqf2g2ega2gf14.ap4m4f.2a3fg2fa14.a2p4m2pa4.anfaoa15.a2p3mpqa5.anaoa15.qpqmpmqa7.aoa15.a3qp3qa8.a16.asqt2quq26.a6vuva24.as2tuv2uva24.as2tuvuva26
		+.a2tu3va26.a2tu2va27.at2uva28.aegva29.aegva28.a4wva27.a4wyva27.2a3va53.
		bat|24|16|13|12|a14111C,b6F6582,c403854,d2D283D,e5B4D6E,f2C263A,g827495,hDB6E6E,i3F364F,jFFFFFF|idle:0;fly:0,1,2,1
		+.a18.a3.aba16.aba2.acba14.abca2.a2cba12.ab2ca2.ad2cba10.ab2cda3.ad2cba2.a4.2ab2cda5.ad2cb2aea2.aef2cda7.a2dc2a2e2a2ef2da9.3a.aeg2egef2a14.aeh2ehea17.a4ea18.ai2eia19.a2ja2
		+1.2a59./105.a4.a9.7a.aea2.aef6a2.7b2a2e2a2ef6ba.d5cb2aeg2egef5cda.adadadc2aeh2ehefdadada3.a.a.2a2.a4e3a.a.a12.ai2eia19.a2ja21.2a83./81.a4.a17.aea2.aea16.a2e2a2ea12.3a.aeg
		+2egef2a9.a2dc2aeh2ehef2da7.ad2cba.a4efb2cda5.ad2cba2.ai2ei2ab2cda3.ad2cba4.a2ja2.ab2cda2.a2cba6.2a4.ab2ca2.acba14.abca2.aba16.aba3.a18.a27.
		bear|46|26|23|16|a1C1518,bA08061,c422F2C,d815F48,e5B4237,fFFFFFF,g1A1316,hCBB393,i1E1519,jBA9C77,k816B57,l251A18,mE7DFC9,nEFEAD9,o834248|idle:0;walk:1,2,3,4;strike:5
		+106.8a34.4a8b2ac2a25.4a13bc3da22.2a16bcd3ed6a15.a18bcd2e2d6b2a12.a3b17dc2d10ba10.a2b14de3dc3b4d3e3dba9.ab15de2dc2b7dfg4d2a8.a17dedcb8d2g4h2ia7.a17dedc11d4j2ia7.ae17dece9d
		+e6ja7.ae19dce7d2e5ka9.ae19dce6de5la10.a5dc8dc5d2c2e4d2e3ja11.a5dc8ec5d3c7e3a12.a4de10c4dec2e3c4a15.a4de6c3ac4dec3eca19.a3d2ec2e2ca3.a3d2ec2e2ca19.a3d2ec2e2ca3.a3d2ec2e2ca
		+19.a4d2ec2e2ca2.a4d2ec2e2ca18.a5dec3eca2.a5dec3eca18.acmcmcm2cmcma2.acmcmcm2cmcma19.5ac5a4.5ac5a63./106.8a34.4a8b2ac2a25.4a13bc3da22.2a16bcd3ed6a15.a18bcd2e2d6b2a12.a3b17
		+dc2d10ba10.a2b14de3dc3b4d3e3dba9.ab15de2dc2b7dfg4d2a8.a17dedcb8d2g4h2ia7.a17dedc11d4j2ia7.ae17dece9de6ja7.ae19dce7d2e5ka9.ae19dce6de5la11.ac5dc4dc5dc2ec2e4d2e3ja13.c5dc4e
		+c5dcea2c7e3a14.a4de6c4deca.ae5c2a17.a4de2c3ac4dea2.a4eca19.a3d2eca3.a3d2ea2.a3e2ca19.a3d2eca3.a3d2ea2.a3e2ca19.a4d2eca2.a4d2ea.a4e2ca18.a5deca2.a5dea.a5eca18.acmcmcmca2.a
		+cmcmcma.acmcmcma19.a5ca4.6a3.6a61./60.8a34.4a8b2ac2a25.4a13bc3da22.2a16bcd3ed6a15.a18bcd2e2d6b2a12.a3b17dc2d10ba10.a2b14de3dc3b4d3e3dba9.ab15de2dc2b7dfg4d2a8.a17dedcb8d2g
		+4h2ia7.a17dedc11d4j2ia7.ae17dece9de6ja7.ae19dce7d2e5ka9.ae19dce6de5la11.a2e11dc5d2c2e4d2e3ja11.a5dc8ec5d3c7e3a12.a5d10c4dec2e3c4a15.a4de6c3ac4dec3eca19.a4dec2e2ca3.a3d2ec
		+3eca19.a3d2ec2e2ca3.a3d2ec2e2ca19.a3d2ec3e2ca2.a4d2ece2ca19.a4d2ec3eca2.a5dec2e2ca18.a5de2cmcma2.acmcmcmc3eca18.acmcmcmc4a4.4a2cmcmcma19.6a14.6a63./106.8a34.4a8b2ac2a25.4
		+a13bc3da22.2a16bcd3ed6a15.a18bcd2e2d6b2a12.a3b17dc2d10ba10.a2b14de3dc3b4d3e3dba9.ab15de2dc2b7dfg4d2a8.a17dedcb8d2g4h2ia7.a17dedc11d4j2ia7.ae17dece9de6ja7.ae19dce7d2e5ka9.
		+ae19dce6de5la8.a5dc12dc4dc2e4d2e3ja9.a5dc12ec5dc7e3a10.a4deca12c4de2c6a13.a4dea.a7c3ac4deca19.a3d2ea2.a3e2ca3.a3d2eca19.a3d2ea2.a3e2ca3.a3d2eca19.a4d2ea.a4e2ca2.a4d2eca18
		+.a5dea.a5eca2.a5deca18.acmcmcma.acmcmcma2.acmcmcmca19.6a3.6a4.a5ca65./60.8a34.4a8b2ac2a25.4a13bc3da22.2a16bcd3ed6a15.a18bcd2e2d6b2a12.a3b17dc2d10ba10.a2b14de3dc3b4d3e3dba
		+9.ab15de2dc2b7dfg4d2a8.a17dedcb8d2g4h2ia7.a17dedc11d4j2ia7.ae17dece9de6ja7.ae19dce7d2e5ka9.ae19dce6de5la10.a5dc13d2ec2e4d2e3ja11.a5dc8ec5d3c7e3a12.a4de10c5dc2e3c4a15.a4de
		+6c3ac4dec3eca19.a3d2ec3eca3.a4dec2e2ca19.a3d2ec2e2ca3.a3d2ec2e2ca19.a4d2ece2ca3.a3d2ec3e2ca18.a5dec2e2ca2.a4d2ec3eca18.acmcmcmc3eca2.a5de2cmcma19.4a2cmcmcma2.acmcmcmc4a25
		+.6a4.6a68./106.8a34.4a8b3a.3a23.4a15bc3da20.2a18bcd3ed6a13.a20bcd2e2d6b2a10.a3b19dc2d10ba8.a2b14de5dc3b4d3e3dba7.ab15de4dc2b7dfg4d2a6.a17de3dcb8d2g4h2ia5.a17de3dc11d4j2ia
		+5.ae17de2dce9dejnjnja6.ae21dce7d2e5oa7.ae15dc5dce6d2e5oa6.a5dc11dc5d2ce5d2ejnjnja6.a5dc11ec4decec2e3d2e4ja7.a4de13c4de2c2a6e3ka8.a4de2a7c3ac3d2e2ca.9a9.a3d2ea.a3e2ca3.a3d
		+2e2ca19.a3d2ea.a4e2ca2.a4d2eca19.a4d2e2a5eca2.a5de2ca18.a5de2acmcmcma2.acmcmcm2ca18.acmcmcma.6a4.a6cma19.6a14.6a64.
		bearBoss|112|92|88|50|a120D10,bDDD5BF,cD1C7AD,d978E7E,e120C10,f493B36,g6B5D53,h322727,i90857C,j231B1D,kBC8B7F,lEFE3AF,mD6AA63,n9F876F,o1A1115,p846B56,q5D4A3E,r231A1C,sE3DBC9,t978E7F,uEFEAD9,v552930,w834248,xE4DCCD|idle:0;walk:1,2,3,4;rear:5;strike:6
		+3533.a110.aba108.a2bca102.a3.d2b2cda7.3a90.aba2edb2c2da.a4.a3fa83.a4.a2bcd2g5d.aba2.af3hf7a75.aba.ed2b2c2d3fi2gd2bca.af2h2f7g3a65.a5.a2bcdgdb2c3d5fd2b2cd3a2f12ga55.a7.aba
		+3.a2b2c2dg5d6fdb2c2dj4g11f2ga45.a7.aba5.a2bca2.ab2c3d13f4dj2g16fga43.aba5.a2bca3.d2b2c2d2e5d17fj2g9fk8fga41.a2bca3ed2b2c2d2edb2c3d4g15fi3fj2g11fk4h4fga38.ed2b2c2digdb2c3d
		+3g5d3g11fi9fjg12fklm8f2a35.egdb2c3d3g5d3g14fi15fjg13fk2mf6n2oa33.e3g5d20fi21fj15fk7n3oa32.e2g21fi27fj16f8p2oa31.e2g16fi26fh3fi2fjh14fh10pa30.e2g11fi24fh5fifh6fjh13f2h9pa3
		+0.e2g6fi30fi15fjh11f2h9qa31.egfi28fhfi22fjh10fh9oa32.e15fh7fh3fi24fh4fjh8f2h8pa33.e7fh7fh5fi22fh7fh5fj2h6f3h6qa33.eg7fh7fi20fh7fh14f2j9h6a34.eg28fh7fh24f4j5a40.e21fh7fh28
		+fh5fge44.eg13fh7fh28fh7fh6fe44.eg5fh7fh28fh7fh14fe44.e6fh28fh7fh22fe44.e27fh7fh28fhfe44.e19fh7fh28f2h6fhfe44.e11fh7fh24f17h2f2hfe44.e2hfh7fh28f21hf4he44.e7h25fh4f29he44.e
		+66he44.ej63h2je44.e2j61h3je45.ej61h2je46.ej60h2je48.ej54h7je48.e4j50h7je49.e5j37h19je49.e7j5h8j18h22je51.e2j9f31j9f8je52.j11f30j9fh4j3r53.a11fh29j9fh2j2rhja53.a11fh29j8f2
		+hjr2h2ja54.a9f2h29j8f2hj3h2ja55.a7f2hj6r21jej8f2hj3h2ja55.a7fhj5hja21e2.a7f2hj3h2ja55.a7fhj5hja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a7f2hj3h2ja55.a6
		+f2hj4h2ja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a8f2hj3h2ja54.a7f2hj4h2ja22.a9fhj4hja54.a8fhj5hja22.a9fhj4hja54.a9fhj5hja21.a10h6ja54.a10h7ja21.aststststsjststsa55.aststststsjtst
		+stsa23.6a3j6a57.7a2j7a192./3533.a110.aba108.a2bca102.a3.d2b2cda7.3a90.aba2edb2c2da.a4.a3fa83.a4.a2bcd2g5d.aba2.af3hf7a75.aba.ed2b2c2d3fi2gd2bca.af2h2f7g3a65.a5.a2bcdgdb2c
		+3d5fd2b2cd3a2f12ga55.a7.aba3.a2b2c2dg5d6fdb2c2dj4g11f2ga45.a7.aba5.a2bca2.ab2c3d13f4dj2g16fga43.aba5.a2bca3.d2b2c2d2e5d17fj2g9fk8fga41.a2bca3ed2b2c2d2edb2c3d4g15fi3fj2g11
		+fk4h4fga38.ed2b2c2digdb2c3d3g5d3g11fi9fjg12fklm8f2a35.egdb2c3d3g5d3g14fi15fjg13fk2mf6n2oa33.e3g5d20fi21fj15fk7n3oa32.e2g21fi27fj16f8p2oa31.e2g16fi26fh3fi2fjh14fh10pa30.e2
		+g11fi24fh5fifh6fjh13f2h9pa30.e2g6fi30fi15fjh11f2h9qa31.egfi28fhfi22fjh10fh9oa32.e15fh7fh3fi24fh4fjh8f2h8pa33.e7fh7fh5fi22fh7fh5fj2h6f3h6qa33.eg7fh7fi20fh7fh14f2j9h6a34.eg
		+28fh7fh24f4j5a40.e21fh7fh28fh5fge44.eg13fh7fh28fh7fh6fe44.eg5fh7fh28fh7fh14fe44.e6fh28fh7fh22fe44.e27fh7fh28fhfe44.e19fh7fh28f2h6fhfe44.e11fh7fh24f17h2f2hfe44.e2hfh7fh28f
		+21hf4he44.e7h25fh4f29he44.e66he44.ej63h2je44.e2j61h3je45.ej61h2je46.ej60h2je48.ej54h7je48.e4j50h7je49.e5j37h19je49.e7j5h8j18h22je51.e5j9f25j9f11jra51.2e2j11f24j9fh7j3rhja
		+52.ej11fh23j9fh5j2r4hja53.j11fh23j8f2h4jr5h2ja54.j9f2h23j8f2h2j2r6h2ja55.a7f2hjr2e20j8f2hjr8h2ja55.a7fhja3.20ej7f2ha.a7h2ja55.a7fhja23.a7f2ha.a7h2ja55.a6f2hja23.a7f2ha.a7
		+h2ja55.a6f2hja23.a7f2ha.a7h2ja55.a6f2hja23.a7f2ha.a7h2ja55.a6f2hja23.a8f2h2a8h2ja54.a7f2hja22.a9fh2a9hja54.a8fhja22.a9fh2a9hja54.a9fhja21.a10h2a10ja54.a10hja21.aststststs
		+a.aststststsa55.aststststsja23.9a3.9a57.a8ja195./3645.a110.aba108.a2bca102.a3.d2b2cda7.3a90.aba2edb2c2da.a4.a3fa83.a4.a2bcd2g5d.aba2.af3hf7a75.aba.ed2b2c2d3fi2gd2bca.af2h
		+2f7g3a65.a5.a2bcdgdb2c3d5fd2b2cd3a2f12ga55.a7.aba3.a2b2c2dg5d6fdb2c2dj4g11f2ga45.a7.aba5.a2bca2.ab2c3d13f4dj2g16fga43.aba5.a2bca3.d2b2c2d2e5d17fj2g9fk8fga41.a2bca3ed2b2c2
		+d2edb2c3d4g15fi3fj2g11fk4h4fga38.ed2b2c2digdb2c3d3g5d3g11fi9fjg12fklm8f2a35.egdb2c3d3g5d3g14fi15fjg13fk2mf6n2oa33.e3g5d20fi21fj15fk7n3oa32.e2g21fi27fj16f8p2oa31.e2g16fi26
		+fh3fi2fjh14fh10pa30.e2g11fi24fh5fifh6fjh13f2h9pa30.e2g6fi30fi15fjh11f2h9qa31.egfi28fhfi22fjh10fh9oa32.e15fh7fh3fi24fh4fjh8f2h8pa33.e7fh7fh5fi22fh7fh5fj2h6f3h6qa33.eg7fh7f
		+i20fh7fh14f2j9h6a34.eg28fh7fh24f4j5a40.e21fh7fh28fh5fge44.eg13fh7fh28fh7fh6fe44.eg5fh7fh28fh7fh14fe44.e6fh28fh7fh22fe44.e27fh7fh28fhfe44.e19fh7fh28f2h6fhfe44.e11fh7fh24f1
		+7h2f2hfe44.e2hfh7fh28f21hf4he44.e7h25fh4f29he44.e66he44.ej63h2je44.e2j61h3je45.ej61h2je46.ej60h2je48.ej54h7je48.e4j50h7je49.e5j37h19je49.e3j9f8j18h5j9f8je51.ej11f30j9fh7j
		+e52.j11fh29j9fh4j3r53.a11fh29j8f2h2j2r2ja54.a9f2h29j8f2hjr2h2ja55.a7f2h30j8f2hj3h2ja55.a7fhj7r21j2ej7f2hj3h2ja55.a7fhj5hja21e2.a7f2hj3h2ja55.a6f2hj4h2ja23.a7f2hj3h2ja55.a
		+6f2hj4h2ja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a8f2hj3h2ja54.a7f2hj4h2ja22.a9fhj4hja54.a8fhj5hja22.a9fhj4hja54.a9fhj5hja21.a10h6ja54.a10h7ja21.astst
		+ststsjststsa55.aststststsjtststsa23.6a3j6a57.7a2j7a192./3533.a110.aba108.a2bca102.a3.d2b2cda7.3a90.aba2edb2c2da.a4.a3fa83.a4.a2bcd2g5d.aba2.af3hf7a75.aba.ed2b2c2d3fi2gd2b
		+ca.af2h2f7g3a65.a5.a2bcdgdb2c3d5fd2b2cd3a2f12ga55.a7.aba3.a2b2c2dg5d6fdb2c2dj4g11f2ga45.a7.aba5.a2bca2.ab2c3d13f4dj2g16fga43.aba5.a2bca3.d2b2c2d2e5d17fj2g9fk8fga41.a2bca3
		+ed2b2c2d2edb2c3d4g15fi3fj2g11fk4h4fga38.ed2b2c2digdb2c3d3g5d3g11fi9fjg12fklm8f2a35.egdb2c3d3g5d3g14fi15fjg13fk2mf6n2oa33.e3g5d20fi21fj15fk7n3oa32.e2g21fi27fj16f8p2oa31.e2
		+g16fi26fh3fi2fjh14fh10pa30.e2g11fi24fh5fifh6fjh13f2h9pa30.e2g6fi30fi15fjh11f2h9qa31.egfi28fhfi22fjh10fh9oa32.e15fh7fh3fi24fh4fjh8f2h8pa33.e7fh7fh5fi22fh7fh5fj2h6f3h6qa33.
		+eg7fh7fi20fh7fh14f2j9h6a34.eg28fh7fh24f4j5a40.e21fh7fh28fh5fge44.eg13fh7fh28fh7fh6fe44.eg5fh7fh28fh7fh14fe44.e6fh28fh7fh22fe44.e27fh7fh28fhfe44.e19fh7fh28f2h6fhfe44.e11fh
		+7fh24f17h2f2hfe44.e2hfh7fh28f21hf4he44.e7h25fh4f29he44.e66he44.ej63h2je44.e2j61h3je45.ej61h2je46.ej60h2je48.ej54h7je48.e4j50h7je49.e5j37h19je49.e7j5h8j18h22je50.a9f37j9f5
		+je49.a11f36j9fhj3e50.a11fh35j9fhj53.a11fh35j8f2hj54.a9f2h35j8f2hj55.a7f2hj2e7r21j4ej8f2hj55.a7fha3.a6h3r18e5.j7f2hj55.a7fha3.a7hja23.j7f2hj55.a6f2ha3.a6h2ja23.j7f2hj55.a6
		+f2ha3.a6h2ja23.j7f2hj55.a6f2ha3.a6h2ja23.j7f2hj55.a6f2ha3.a6h2ja23.j8f2hj54.a7f2ha2.a7h2ja22.j9fhj54.a8fha2.a8hja22.j9fhj54.a9fha.a9hja21.j10hj54.a10ha.a10ja21.jststststs
		+j55.aststststsa2.aststststsa23.9j57.9a4.9a189./3645.a110.aba108.a2bca102.a3.d2b2cda7.3a90.aba2edb2c2da.a4.a3fa83.a4.a2bcd2g5d.aba2.af3hf7a75.aba.ed2b2c2d3fi2gd2bca.af2h2f
		+7g3a65.a5.a2bcdgdb2c3d5fd2b2cd3a2f12ga55.a7.aba3.a2b2c2dg5d6fdb2c2dj4g11f2ga45.a7.aba5.a2bca2.ab2c3d13f4dj2g16fga43.aba5.a2bca3.d2b2c2d2e5d17fj2g9fk8fga41.a2bca3ed2b2c2d2
		+edb2c3d4g15fi3fj2g11fk4h4fga38.ed2b2c2digdb2c3d3g5d3g11fi9fjg12fklm8f2a35.egdb2c3d3g5d3g14fi15fjg13fk2mf6n2oa33.e3g5d20fi21fj15fk7n3oa32.e2g21fi27fj16f8p2oa31.e2g16fi26fh
		+3fi2fjh14fh10pa30.e2g11fi24fh5fifh6fjh13f2h9pa30.e2g6fi30fi15fjh11f2h9qa31.egfi28fhfi22fjh10fh9oa32.e15fh7fh3fi24fh4fjh8f2h8pa33.e7fh7fh5fi22fh7fh5fj2h6f3h6qa33.eg7fh7fi2
		+0fh7fh14f2j9h6a34.eg28fh7fh24f4j5a40.e21fh7fh28fh5fge44.eg13fh7fh28fh7fh6fe44.eg5fh7fh28fh7fh14fe44.e6fh28fh7fh22fe44.e27fh7fh28fhfe44.e19fh7fh28f2h6fhfe44.e11fh7fh24f17h
		+2f2hfe44.e2hfh7fh28f21hf4he44.e7h25fh4f29he44.e66he44.ej63h2je44.e2j61h3je45.ej61h2je46.ej60h2je48.ej54h7je48.e4j50h7je49.e5j37h19je49.e3j9f8j18h5j9f8je51.ej11f30j9fh7je5
		+2.j11fh29j9fh4j3r53.a11fh29j8f2h2j2r2ja54.a9f2h29j8f2hjr2h2ja55.a7f2h30j8f2hj3h2ja55.a7fhj7r21j2ej7f2hj3h2ja55.a7fhj5hja21e2.a7f2hj3h2ja55.a6f2hj4h2ja23.a7f2hj3h2ja55.a6f
		+2hj4h2ja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a8f2hj3h2ja54.a7f2hj4h2ja22.a9fhj4hja54.a8fhj5hja22.a9fhj4hja54.a9fhj5hja21.a10h6ja54.a10h7ja21.aststst
		+stsjststsa55.aststststsjtststsa23.6a3j6a57.7a2j7a192./1304.3a108.a3fa106.af3hf7a99.af2h2f7g3a96.2a2f12ga94.a4g11f2ga92.a2g16fga90.a2g9fk8fga88.a2g11fk4h4fga82.a4.ag12fklm
		+8f2a79.aba3.jg13fk2mf6n2oa77.a2bca.aj15fk7n3oa76.a2b2c2dbj16f8p2oa72.a3.ab2c2d2bjh14fhpupupupupa72.aba3.4adbcjh13f2h8va72.a2bca5.2a4jh11f2h8wva71.a2b2cda3.a6fjh10fh9wva71
		+.ab2c2da2.a8fjh8f2h8wva71.2e5d3ej8fhjh7f2hupupupu2pa68.a.e4g6fj8f2hj2h5f2h8pa68.abd3g9fj8fh3j8h5q2a68.a2bcd10fifj7f2hjg5j8a69.a2b2c2d3fi5fh2fj7fhjgea.a73.a4.ab2c3d9fh3fj6
		+fhjfe75.aba2.2e5d14fj7hjie74.a2bcde3g18fjstststsjfge72.a2b2c2d2g16fi2fjsjsjsjsjfge66.a5.db2c3d12fifh7fjfjfjfj3fge64.aba2.2eg5d7fi7fh17fge56.a6.a2bcde4g5fi5fh24fife55.aba4
		+.a2b2c2d2gfi32fh5fe54.a2bca3edb2c3d28fh7fh5fe52.ed2b2c2di2g5d21fh7fh13fe51.egdb2c3d3g18fh7fh21fe50.e3g5d20fifh28fhe49.e2g21fi28fh7fhe48.e2g16fi26fh7fh5fh2fe47.e2g11fi24fh
		+7fh8f2h3f3he46.e2g6fi22fh7fh14f10he46.egfi20fh7fh21f11he46.e15fh7fh23f17he46.e7fh7fh28f19hje45.eg7fh7fi20fh6f19h2je45.eg28fh7fh5f19h3je45.e21fh7fh10f22h2je45.eg13fh7fh15f
		+24h2je46.eg5fh7fh22f22hjh3je46.e6fh28f23h5je47.e27fh5f23h7je47.e19fh7fh2f25h8je47.e11fh7fh6f28h8je48.e2hfh7fh9f29h11je49.e7h11f29h12j2e50.e44h14je52.ej40h16je53.e2j36h18j
		+e55.ej35h18je56.ej32h20je58.ej27h20j4e59.e4j20h21j3e63.e5j13h24j3e66.e7j5h27j3e70.e2j9f24j3e74.j11f19j4e77.a11fh14j4e81.a11fh10j4e86.a9f2h4j4r2e91.a7f2hj4r2ja94.a7fhj5hja
		+95.a7fhj5hja95.a6f2hj4h2ja95.a6f2hj4h2ja95.a6f2hj4h2ja95.a6f2hj4h2ja95.a7f2hj4h2ja94.a8fhj5hja94.a9fhj5hja93.a10h7ja93.aststststsjtststsa95.7a2j7a192./3533.a110.aba108.a2
		+bca102.a3.d2b2cda100.aba2edb2c2da.a5.3a84.a4.a2bcd2g5d.aba3.a3fa82.aba.ed2b2c2d3fi2gd2bca.af3hf7a68.a5.a2bcdgdb2c3d5fd2b2cd2af2h2f7gaxa56.a7.aba3.a2b2c2dg5d6fdb2c2d3a2f8g
		+2x2ga46.a7.aba5.a2bca2.ab2c3d13f5dj4g5f3x3f2ga44.aba5.a2bca3.d2b2c2d2e5d18fj2g4f4x8fga42.a2bca3ed2b2c2d2edb2c3d4g15fi4fj2g3f2x4fk8fga39.ed2b2c2digdb2c3d3g5d3g11fi9fj2g11f
		+k4h4fga37.egdb2c3d3g5d3g14fi15fjg12fklm8f2a34.e3g5d20fi21fjg13fk2mf6n2oa32.e2g21fi27fj15fk7n3oa31.e2g16fi26fh3fi2fj16f8p2oa30.e2g11fi24fh5fifh6fjh14fhpupupupupa30.e2g6fi3
		+0fi10f5jh13f2h8va31.egfi28fhfi14f2j5fjh11f2h8wva31.e15fh7fh3fi19fj8fjh10fh9wva31.e7fh7fh5fi22fhfj10fjh8f2h8wva31.eg7fh7fi20fh7fhfj7f4hjh7f2hupupupu2pa31.eg28fh7fh10fj5h7j
		+2h5f2h8pa32.e21fh7fh19f5j4fh2f2j8h5q2a32.eg13fh7fh28fh7fh4f3j10a34.eg5fh7fh28fh7fh14fe44.e6fh28fh7fh22fe44.e27fh7fh28fhfe44.e19fh7fh28f2h6fhfe44.e11fh7fh24f17h2f2hfe44.e2
		+hfh7fh28f21hf4he44.e7h25fh4f29he44.e66he44.ej63h2je44.e2j61h3je45.ej61h2je46.ej60h2je48.ej54h7je48.e4j50h7je49.e5j37h19je49.e7j5h8j18h22je51.e3j9f47je52.ej11f43j3r54.a11f
		+h40j2rhja54.a11fh39jr2h2ja55.a9f2h37j2r3h2ja56.a7f2hj5r21j7e4r5h2ja56.a7fhj4hja21e8.a7h2ja56.a7fhj4hja29.a7h2ja56.a6f2hj3h2ja29.a7h2ja56.a6f2hj3h2ja29.a7h2ja56.a6f2hj3h2j
		+a29.a7h2ja56.a6f2hj3h2ja29.a8h2ja55.a7f2hj3h2ja28.a9hja55.a8fhj4hja28.a9hja55.a9fhj4hja27.a10ja55.a10h6ja27.aststststsa56.aststststsjststsa29.9a58.6a3j6a192.
		cat|24|17|14|10.5|a211713,bC89961,cD3AB75,dA2744B,e83C66E,f6B4C39,g15111A,hDD909C,iEEDEC0,j926D49,kCEBA9B|idle:0;walk:1,2,3,4
		+13.a5.a6.2a8.aba3.aba4.abca7.a2b3a2bca2.abca8.a2b3c3ba2.aba9.abdbd2bdba2.aba9.abe3be2ba2.abd9afbg3bg2ba3.abf9cf2bh3ba5.fc2bd2bd2bdbf4ia6.a3bd2bd2bd2bf3a7.aj10bja11.f2bf3i
		+f2b2fa11.a2b3faf2bfja11.a2bfja.a2bfja11.a2ifka.a2ifka12.4a3.4a33./13.a5.a6.2a8.aba3.aba4.abca7.a2b3a2bca2.abca8.a2b3c3ba2.aba9.abdbd2bdba2.aba9.abe3be2ba2.abd9afbg3bg2ba3
		+.abf9cf2bh3ba5.fc2bd2bd2bdbf4ia6.a3bd2bd2bd2bf3a7.aj10bja11.af2bfif2b3fja11.f2bfaf2bfa2ja11.f2bf.a2b2a2ja11.f2if.a2i2a2ka12.2f3.2a2.2a32./2.2a8.aba3.aba4.abca7.a2b3a2bca2
		+.abca8.a2b3c3ba2.aba9.abdbd2bdba2.aba9.abe3be2ba2.abd9afbg3bg2ba3.abf9cf2bh3ba5.fc2bd2bd2bdbf4ia6.a3bd2bd2bd2bf3a7.aj10bja11.aj5if2bfa12.a2b3faf2bfja11.a2bfja.a2bfja11.a2
		+bfka.a2ifja11.a2ifa3.af2ka12.2a7.2a33./13.a5.a6.2a8.aba3.aba4.abca7.a2b3a2bca2.abca8.a2b3c3ba2.aba9.abdbd2bdba2.aba9.abe3be2ba2.abd9afbg3bg2ba3.abf9cf2bh3ba5.fc2bd2bd2bdb
		+f4ia6.a3bd2bd2bd2bf3a7.aj10bja10.a2bf5if2bf11.a2b5faf2bf11.a2b2a2ja.f2bf11.a2i2a2ka.f2if12.2a2.2a3.2f34./2.2a8.aba3.aba4.abca7.a2b3a2bca2.abca8.a2b3c3ba2.aba9.abdbd2bdba2
		+.aba9.abe3be2ba2.abd9afbg3bg2ba3.abf9cf2bh3ba5.fc2bd2bd2bdbf4ia6.a3bd2bd2bd2bf3a7.aj10bja11.f2bf4ikj2fa11.a2b3faf2bfja11.a2bfja.a2bfja11.a2ifja.a2bfka12.af2ka.a2ifa15.2a3
		+.2a35.
		chicken|18|18|15|7.5|a241D22,bC56661,cFAF8F0,d1E1519,eD0AC64,fB5ADB7,gAE874F,h974A50,iDAD4D1|idle:0;walk:1,2,3,4;alt:5
		+8.a2baba12.a4ba12.a4ca5.a5.a3cdcea3.aca2.2af4cega3.a2c2a3cf3cba4.a7cf3caha3.ai3c2i2c3f.a4.ai2c4i3ca7.ai2c2i4ca7.a2i6cia8.a7ia10.a4faea11.a3faea12.7a11.a2ea3ea11.6a24./8.a
		+2baba12.a4ba12.a4ca5.a5.a3cdcea3.aca2.2af4cega3.a2c2a3cf3cba4.a7cf3caha3.ai3c2i2c3f.a4.ai2c4i3ca7.ai2c2i4ca7.a2i6cia8.a7ia10.a3faea12.2afaea14.5a13.2a3ea13.4a25./8.a4ba12
		+.a4ca5.a5.a3cdcea3.aca2.2af4cega3.a2c2a3cf3cba4.a7cf3caha3.ai3c2i2c3f.a4.ai2c4i3ca7.ai2c2i4ca7.a2i6cia8.a7ia10.a5fa12.a3faea12.4aea12.a2e4a12.3a3ea14.3a24./8.a2baba12.a4b
		+a12.a4ca5.a5.a3cdcea3.aca2.2af4cega3.a2c2a3cf3cba4.a7cf3caha3.ai3c2i2c3f.a4.ai2c4i3ca7.ai2c2i4ca7.a2i6cia8.a7ia10.a5faea10.3f3aea10.4a.4a9.a3e2a3ea9.3a2.3a23./8.a4ba12.a4
		+ca5.a5.a3cdcea3.aca2.2af4cega3.a2c2a3cf3cba4.a7cf3caha3.ai3c2i2c3f.a4.ai2c4i3ca7.ai2c2i4ca7.a2i6cia8.a7ia10.a4faea11.a3faea12.ae5a11.4a3ea10.a3e3a12.3a27./73.a16.aca2.4a9
		+.a2c2a4c4a.a3.a9cf2baba2.ai3c2i3cf4ba2.ai2c4i2cf4ca3.ai2c2i2cf3cdcea2.a2i5cf4cega3.a5iaef3cba5.a4faef3caha5.a3f3af2a.a7.a2ea3ea11.6a24.
		cinderBat|24|16|13|12|a1D110F,bC4836F,cB36F51,d7C4D3A,e48302A,f24181C,g755E60,hDFCB78,i322121,jFFFFFF|idle:0;fly:0,1,2,1
		+.a18.a3.aba16.aba2.acba14.abca2.a2cba12.ab2ca2.ad2cba10.ab2cda3.ad2cba2.a4.2ab2cda5.ad2cb2aea2.aef2cda7.a2dc2a2e2a2ef2da9.3a.aeg2egef2a14.aeh2ehea17.a4ea18.ai2eia19.a2ja2
		+1.2a59./105.a4.a9.7a.aea2.aef6a2.7b2a2e2a2ef6ba.d5cb2aeg2egef5cda.adadadc2aeh2ehefdadada3.a.a.2a2.a4e3a.a.a12.ai2eia19.a2ja21.2a83./81.a4.a17.aea2.aea16.a2e2a2ea12.3a.aeg
		+2egef2a9.a2dc2aeh2ehef2da7.ad2cba.a4efb2cda5.ad2cba2.ai2ei2ab2cda3.ad2cba4.a2ja2.ab2cda2.a2cba6.2a4.ab2ca2.acba14.abca2.aba16.aba3.a18.a27.
		cow|34|24|21|14|a1E1B22,bE3D9C1,cBCAE90,dAEA7B4,e38343E,fF6F2EA,g1E1519,hE6A9B0,iD7D1D3,j824C5C,kC4818F,lCA8B98,mEAB5BC,n3A3038|idle:0;walk:1,2,3,4;alt:5
		+22.2a31.a2ba29.abc5a12.13ad3e5f2a8.2a14fd3e6fa6.a4f4e6f2efde4fg3fa4.a4f6e4f4ed5fgf2ha3.ai4f6e5f3ed6f3ha2.aia5f4e7f2efdi3f2hjha2.aia12f2e5fd2i2f4ha2.aia11f4e5fd3i3ka3.aiai
		+10f4e4fi7a4.aia2i10f2e4f2ia10.ae2a3i12f3ia11.ae2a3fd7id3f3dia11.a.a3f9d3f2d2ia13.a2fi5d3ad2fid2ida13.a2fidlmla3.a2fid2ida13.a2fidilda3.a2fid2ida13.a2fid2ida3.a2fid2ida13.
		+a3nd3na3.a3nd3na13.a3nd3na3.a3nd3na14.3a.3a5.3a.3a45./22.2a31.a2ba29.abc5a12.13ad3e5f2a8.2a14fd3e6fa6.a4f4e6f2efde4fg3fa4.a4f6e4f4ed5fgf2ha3.ai4f6e5f3ed6f3ha2.aia5f4e7f2e
		+fdi3f2hjha2.aia12f2e5fd2i2f4ha2.aia11f4e5fd3i3ka3.aiai10f4e4fi7a4.aia2i10f2e4f2ia10.ae2a3i12f3ia11.aea.ad3fd3id3fdi3d3ia9.a3.d3f5d3f2d3a3ia13.d2fi3dad2fida2.a2ida13.d2fid
		+a2.a2fia3.a2ida13.d2fid3.a2fia3.a2ida13.d2fid3.a2fia3.a2ida13.d3nd3.a3na3.a3na13.d3nd3.a3na3.a3na14.3d5.3a5.3a43./21.a2ba29.abc5a12.13ad3e5f2a8.2a14fd3e6fa6.a4f4e6f2efde4
		+fg3fa4.a4f6e4f4ed5fgf2ha3.ai4f6e5f3ed6f3ha2.aia5f4e7f2efdi3f2hjha2.aia12f2e5fd2i2f4ha2.aia11f4e5fd3i3ka3.aiai10f4e4fi7a4.aia2i10f2e4f2ia10.ae2a3i12f3ia11.aea.a2d8id3f2da1
		+3.a.a3f9d3f2d2ia13.a3f5d3ad2fid3ia13.a2fidlmla3.a2fid2ida13.a2fidilda3.a2fid2ida13.a2fid2ida3.a2fid2ida13.a2fid3na3.a3nd2ida13.a3nd3na3.a3nd3na13.a3n4a5.4a3na14.3a13.3a45
		+./22.2a31.a2ba29.abc5a12.13ad3e5f2a8.2a14fd3e6fa6.a4f4e6f2efde4fg3fa4.a4f6e4f4ed5fgf2ha3.ai4f6e5f3ed6f3ha2.aia5f4e7f2efdi3f2hjha2.aia12f2e5fd2i2f4ha2.aia11f4e5fd3i3ka3.ai
		+ai10f4e4fi7a4.aia2i10f2e4f2ia10.ae2a3i12f3ia11.ad3f2d10id3fd13.d3fda11d3fd13.a2fia.7d3ad2fid13.a2fia2.amlida3.d2fid13.a2fia3.l2ida3.d2fid13.a2fia3.a2ida3.d2fid13.a3na3.a3
		+na3.d3nd13.a3na3.a3na3.d3nd14.3a5.3a5.3d47./21.a2ba29.abc5a12.13ad3e5f2a8.2a14fd3e6fa6.a4f4e6f2efde4fg3fa4.a4f6e4f4ed5fgf2ha3.ai4f6e5f3ed6f3ha2.aia5f4e7f2efdi3f2hjha2.aia
		+12f2e5fd2i2f4ha2.aia11f4e5fd3i3ka3.aiai10f4e4fi7a4.aia2i10f2e4f2ia10.ae2a3i12f3ia11.ae2a3fd11i3dia11.a.a3f9d3f2d2ia13.a2fi5d3ad3fd2ida13.a2fidlmla3.a2fid2ida13.a2fidilda3
		+.a2fid2ida13.a2fid2ida3.a2fid2ida13.a3nd2ida3.a2fid3na13.a3nd3na3.a3nd3na14.4a3na3.a3n4a19.3a5.3a49./108.15a17.2a15fa15.a4f4e6f2e2fa13.a4f6e4f4e2fa11.ai4f6e5f3e2fa10.aia5
		+f4e7f2e2f3a8.aia12f2e6fd2ba7.aia11f4e4fdbc5a4.aiai10f4e3fd3e5f2a2.aia2i10f2e4fid3e6fa.ae2a3i12f3i2ae4fg3f2ae2a3fd7id3f3did5fgf2ha.a.a3f9d3f2d2id6f3ha3.a2fi5d3ad2fid2id2ai
		+3f2hjha3.a2fidlmla3.a2fid2id2a2i2f4ha3.a2fidilda3.a2fid2ida.a3i3ka4.a2fid2ida3.a2fid2ida2.6a5.a3nd3na3.a3nd3na13.a3nd3na3.a3nd3na14.3a.3a5.3a.3a45.
		crawler|36|18|14|18|a281F2E,b4F3F58,c17121C,d35293E,e8A7696,f695374,gB4A5AD,hC96962,iECAEA2,j493A54,kD2C7B1,l968878,m130E18|idle:0;walk:1,2,3,4;strike:5
		+149.ab3.ab.2c2.2c2.db3.ab13.ab3.dbc2e2c2e2cebc2.db2c10.ababcdbeb2f2e2f2ebfbcdbebec9.abab2ebfb8fbfbdebfbfec8.abcebfb2fbfg4fb2fbdbfhb2fec7.abefbfb2fb6fb2fbdb2fbhifc6.abcj2f
		+bj3fbj3fbj3fbj3fb2fkc5.ab.c2jb14jbd2jfbjlkc5.ab2.cdb14db.2cjbclc6.ab3.ab13cab3.db.c6.ab3.ab15.ab3.ab7.2m3.2m15.2m3.2m77./151.b3.a.2c2.2c2.2cb3.a12.a2.b2.bdc2e2c2ecde2b2.b
		+d2c10.2a.2bc2be2f2e2f2efbebcb3ec8.a2.bc2b2fb8fb2f2bfb2fec7.a2.be2bgfb2fg4fb3f2bfbi2fec6.a.cb2fb3fb6fb3f2bfbfhifc5.a2.cbf2bj3fbj3fbj3f2b2fb3fkc4.a3.bjb16jdbjbfjlkc4.a3.bcb
		+14d2c.bcbjdlc5.a2.b2.bd12cd3.b.bcac5.a3.b.b.a13.a3.b.b.a5.m3.m.m.m13.m3.m.m.m76./113.ab3.ab.2c2.2c2.db3.ab13.ab3.dbc2e2c2e2cebc2.db2c10.ababcdbeb2f2e2f2ebfbcdbebec9.abab2
		+ebfb8fbfbdebfbfec8.abcebfb2fbfg4fb2fbdbfhb2fec7.abefbfb2fb6fb2fbdb2fbhifc6.abcj2fbj3fbj3fbj3fbj3fb2fkc5.ab.c2jb14jbd2jfbjlkc5.ab2.cdb14db.2cjbclc6.ab3.ab13cab3.db.c6.ab3.
		+ab15.ab3.ab7.ab3.ab15.ab3.ab7.2m3.2m15.2m3.2m77./150.a5.b2c2.2c2.cd5.b12.ba2.a2cb2e2c2e2cbec.ac2bc11.2bacd2e2bf2e2f2ebfecdebebc9.ba.b2efbfb6fbfbfdeb2fbec8.bacb2fgbfbfg4fb
		+fbfdbfhibfec7.bdefb2fb2fb4fb2fbfdb3fhbfc6.b.dj2fbjb2fbj3fbj2f2bj4fbfkc5.b.ac4jb11jbjd2j2fjbkc5.b.a.dc2db11dbcacd2jcbc6.ba2.a.cb12cb.a.a2c.b6.b.a.a3.b13.b.a.a3.b5.m.m.m3.m
		+13.m.m.m3.m75./113.ab3.ab.2c2.2c2.db3.ab13.ab3.dbc2e2c2e2cebc2.db2c10.ababcdbeb2f2e2f2ebfbcdbebec9.abab2ebfb8fbfbdebfbfec8.abcebfb2fbfg4fb2fbdbfhb2fec7.abefbfb2fb6fb2fbdb
		+2fbhifc6.abcj2fbj3fbj3fbj3fbj3fb2fkc5.ab.c2jb14jbd2jfbjlkc5.ab2.cdb14db.2cjbclc6.ab3.ab13cab3.db.c6.ab3.ab15.ab3.ab7.ab3.ab15.ab3.ab7.2m3.2m15.2m3.2m77./62.4c3.c27.c4ec.c
		+kc23.abce2fbfecklc13.2c2.2c2.cdbab2fbibfelc11.3c2e2c2e2c2eb.d3bfhbfc10.2c3e2f2e2f2efbe2cjbm2fbfc9.c2e12fbfecdbj2fjbc8.cebfg2fbfg4fgb3feb2c2jclmc6.cebfb2fbfb6fb4fb2.2c.clc
		+6.cjb2fbfb2fb4fb4fbc6.c7.ab4jb13jc14.ab.2cdb12d2c14.ab3.ab13c16.ab3.ab28.2m3.2m100.
		crow|20|18|15|9.5|a0F0F16,b5F5F79,c46465C,d2E2E3F,e1E1E2A,fE2CD81,gA7A7AF,h73737D,i898993|idle:0;fly:0,1,2,1
		+9.2a17.abca15.ab3ca13.ab4ca12.ab4cda11.ab4c2da11.a4c2de2a8.a2.a4de3ba6.aea2.2a2e4bd2a4.a2e4a2d2bf2d2ga4.a2e10dh2ga4.ae10d3a6.a9da10.ae5dea12.2a2i3a15.2a50./111.3a8.a7.a3b
		+a6.a2e4a5ebd2a4.ae2b7cded2ga4.aeb5c2de2dh2ga4.a2e4d2e3d3a6.ad4e4da10.ae5dea12.2a2i3a15.2a70./91.3a8.a7.a3ba6.aea4.2a4bd2a4.a2e2a4e2bf2d2ga4.a3e4de4dh2ga4.ae4c2de3d3a6.eb4
		+c2deda10.eb4cdea12.eb4ce14.ab2cda15.abda17.2a49.
		elephant|64|46|40|26|a1D1B26,bAFB1B9,c4A4A5B,d9598A9,e686979,fAF93A3,gFFFFFF,h1E1519,iA39983,jF1ECDB,k3B3747,lC8BFA4,mD9D3C6,nAEA89F|idle:0;walk:1,2,3,4;strike:5
		+295.7a35.16a4.2a7b2a28.5a16b4a11b2a23.3a23bc14ba15.2a3.2a25b6c9d2ba13.adea.a9b18dc5bc10dba11.adea.a4b23dcb5dbc10dba10.ade2a3b24dcb7dbc10da10.adec2b25dcb2d4f4dcdgh7da9.ade
		+cb26dcbd7f2dcd2h7da9.adcb27dc2d8fdc11da8.adcb7de19dc2d7f2dc11da8.adc8de19dc2d6f2dec5de5da9.ac9de17dece2d5f2dec2d3i6da9.ac9de17dece3d3f2dec2di3j2i3dea8.akce28dce7dec2di2l3
		+j2idia9.ace28dc2e5dec4ei3l3jiji10.c2e28dc2e3d2ec4a.ai2l4ji11.a2e28dc5ea7.a2i3lia12.a3e25d2e4ca8.abd3iea13.a6e17d6e2a11.ab5ea14.2a25e2a13.ab3dea13.a8d14c8dc5ea5.ab4dea13.a
		+7de7c6ac7dec4eca5.ab5ea13.a7dec4eca6.a7dec4eca5.ab3dea14.a6d2ec3e2ca6.a6d2ec3e2ca5.ab3dea14.ab5d2ec3e2ca6.ab5d2ec3e2ca5.ab4ea14.ab5d2ec3e2ca6.ab5d2ec3e2ca6.ab3dea13.ab2de
		+2d2e2c2e2ca6.ab2de2d2e2c2e2ca6.ab3dea13.ab3ded2ecece2ca6.ab3ded2ecece2ca7.ab3ea13.ab5d2ec3e2ca6.ab5d2ec3e2ca7.ab3dea12.ab5d2ec3e2ca6.ab5d2ec3e2ca7.ab4da12.ab5d2ec3e2ca6.a
		+b5d2ec3e2ca8.a2e2da12.ab5d2ec3e2ca6.ab5d2ec3e2ca9.a2ea13.ab6dec4eca6.ab6dec4eca10.2a14.a8dec4eca5.a8dec4eca25.amdmdm3decn3eca5.amdmdm3decn3eca26.6a3c6a7.6a3c6a278./295.7a
		+35.16a4.2a7b2a28.5a16b4a11b2a23.3a23bc14ba15.2a3.2a25b6c9d2ba13.adea.a9b18dc5bc10dba11.adea.a4b23dcb5dbc10dba10.ade2a3b24dcb7dbc10da10.adec2b25dcb2d4f4dcdgh7da9.adecb26dc
		+bd7f2dcd2h7da9.adcb27dc2d8fdc11da8.adcb7de19dc2d7f2dc11da8.adc8de19dc2d6f2dec5de5da9.ac9de17dece2d5f2dec2d3i6da9.ac9de17dece3d3f2dec2di3j2i3dea8.akce28dce7dec2di2l3j2idia
		+9.ace28dc2e5dec4ei3l3jiji10.c2e28dc2e3d2ec4a.ai2l4ji11.a2e28dc5ea7.a2i3lia12.a3e25d2e4ca8.abd3iea13.a6e17d6e2a11.ab5ea14.2a25e2a13.ab3dea15.a8d10c8d2a8ea3.ab4dea15.a7de3c
		+6ac7de2a7eca3.ab5ea15.a7de2ca6.a7de2a7eca3.ab3dea16.a6d2e2ca6.a6d2e2a6e2ca3.ab3dea16.ab5d2e2ca6.ab5d2e2ad5e2ca3.ab4ea16.ab5d2e2ca6.ab5d2e2ad5e2ca4.ab3dea15.ab2de2d2e2ca6.
		+ab2de2d2e2ad2ec2e2ca4.ab3dea15.ab3ded2e2ca6.ab3ded2e2ad3ece2ca5.ab3ea15.ab5d2e2ca6.ab5d2e2ad5e2ca5.ab3dea14.ab5d2e2ca6.ab5d2e2ad5e2ca5.ab4da14.ab5d2e2ca6.ab5d2e2ad5e2ca6.
		+a2e2da14.ab5d2e2ca6.ab5d2e2ad5e2ca7.a2ea15.ab6de2ca6.ab6de2ad6eca8.2a16.a8de2ca5.a8dec8eca25.amdmdm3de2ca5.amdmdm3decnenen3eca26.2a7c2a7.9a.9a276./231.7a35.16a4.2a7b2a28.
		+5a16b4a11b2a23.3a23bc14ba15.2a3.2a25b6c9d2ba13.adea.a9b18dc5bc10dba11.adea.a4b23dcb5dbc10dba10.ade2a3b24dcb7dbc10da10.adec2b25dcb2d4f4dcdgh7da9.adecb26dcbd7f2dcd2h7da9.ad
		+cb27dc2d8fdc11da8.adcb7de19dc2d7f2dc11da8.adc8de19dc2d6f2dec5de5da9.ac9de17dece2d5f2dec2d3i6da9.ac9de17dece3d3f2dec2di3j2i3dea8.akce28dce7dec2di2l3j2idia9.ace28dc2e5dec4e
		+i3l3jiji10.c2e28dc2e3d2ec4a.ai2l4ji11.a2e28dc5ea7.a2i3lia12.a3e25d2e4ca8.abd3iea13.a6e17d6e2a11.ab5ea14.2a25e2a13.ab3dea17.2a17c8da11.ab4dea13.a8d7c6ac7dec5ea5.ab5ea13.a7
		+dec4eca6.a7dec4eca5.ab3dea14.a7dec3e2ca6.a6d2ec4eca5.ab3dea14.a6d2ec3e2ca6.ab5d2ec3e2ca5.ab4ea14.ab5d2ec3e2ca6.ab5d2ec3e2ca6.ab3dea13.ab5d2e2c2e2ca6.ab2de2d2ec3e2ca6.ab3d
		+ea13.ab2de2d2ecece2ca6.ab3ded2e2c2e2ca7.ab3ea13.ab3ded2ec3e2ca6.ab5d2ecece2ca7.ab3dea12.ab5d2ec3e2ca6.ab5d2ec3e2ca7.ab4da12.ab5d2ec3e2ca6.ab5d2ec3e2ca8.a2e2da12.ab5d2ec3e
		+2ca6.ab5d2ec3e2ca9.a2ea13.ab5d2ec4eca6.ab6dec3e2ca10.2a14.ab6dec5eca5.a8dec3eca26.a8decn3eca5.amdmdm3dec4eca25.amdmdm3dec5a7.5a4cen3eca26.9a19.9a278./295.7a35.16a4.2a7b2a
		+28.5a16b4a11b2a23.3a23bc14ba15.2a3.2a25b6c9d2ba13.adea.a9b18dc5bc10dba11.adea.a4b23dcb5dbc10dba10.ade2a3b24dcb7dbc10da10.adec2b25dcb2d4f4dcdgh7da9.adecb26dcbd7f2dcd2h7da9
		+.adcb27dc2d8fdc11da8.adcb7de19dc2d7f2dc11da8.adc8de19dc2d6f2dec5de5da9.ac9de17dece2d5f2dec2d3i6da9.ac9de17dece3d3f2dec2di3j2i3dea8.akce28dce7dec2di2l3j2idia9.ace28dc2e5de
		+c4ei3l3jiji10.c2e28dc2e3d2ec4a.ai2l4ji11.a2e28dc5ea7.a2i3lia12.a3e25d2e4ca8.abd3iea13.a6e17d6e2a11.ab5ea14.2a25e2a13.ab3dea11.a8d18c8dcea7.ab4dea11.a7de11c6ac7de2ca7.ab5e
		+a11.a7de2a7eca6.a7de2ca7.ab3dea12.a6d2e2a6e2ca6.a6d2e2ca7.ab3dea12.ab5d2e2ad5e2ca6.ab5d2e2ca7.ab4ea12.ab5d2e2ad5e2ca6.ab5d2e2ca8.ab3dea11.ab2de2d2e2ad2ec2e2ca6.ab2de2d2e2
		+ca8.ab3dea11.ab3ded2e2ad3ece2ca6.ab3ded2e2ca9.ab3ea11.ab5d2e2ad5e2ca6.ab5d2e2ca9.ab3dea10.ab5d2e2ad5e2ca6.ab5d2e2ca9.ab4da10.ab5d2e2ad5e2ca6.ab5d2e2ca10.a2e2da10.ab5d2e2a
		+d5e2ca6.ab5d2e2ca11.a2ea11.ab6de2ad6eca6.ab6de2ca12.2a12.a8dec8eca5.a8de2ca25.amdmdm3decnenen3eca5.amdmdm3de2ca26.9a.9a7.2a7c2a280./231.7a35.16a4.2a7b2a28.5a16b4a11b2a23.
		+3a23bc14ba15.2a3.2a25b6c9d2ba13.adea.a9b18dc5bc10dba11.adea.a4b23dcb5dbc10dba10.ade2a3b24dcb7dbc10da10.adec2b25dcb2d4f4dcdgh7da9.adecb26dcbd7f2dcd2h7da9.adcb27dc2d8fdc11d
		+a8.adcb7de19dc2d7f2dc11da8.adc8de19dc2d6f2dec5de5da9.ac9de17dece2d5f2dec2d3i6da9.ac9de17dece3d3f2dec2di3j2i3dea8.akce28dce7dec2di2l3j2idia9.ace28dc2e5dec4ei3l3jiji10.c2e2
		+8dc2e3d2ec4a.ai2l4ji11.a2e28dc5ea7.a2i3lia12.a3e25d2e4ca8.abd3iea13.a6e17d6e2a11.ab5ea14.2a25e2a13.ab3dea13.a8d18cac8ea5.ab4dea13.a7de7c6ac8dc4eca5.ab5ea13.a7dec4eca6.a7d
		+ec4eca5.ab3dea14.a6d2ec4eca6.a7dec3e2ca5.ab3dea14.ab5d2ec3e2ca6.a6d2ec3e2ca5.ab4ea14.ab5d2ec3e2ca6.ab5d2ec3e2ca6.ab3dea13.ab2de2d2ec3e2ca6.ab5d2e2c2e2ca6.ab3dea13.ab3ded2
		+e2c2e2ca6.ab2de2d2ecece2ca7.ab3ea13.ab5d2ecece2ca6.ab3ded2ec3e2ca7.ab3dea12.ab5d2ec3e2ca6.ab5d2ec3e2ca7.ab4da12.ab5d2ec3e2ca6.ab5d2ec3e2ca8.a2e2da12.ab5d2ec3e2ca6.ab5d2ec
		+3e2ca9.a2ea13.ab6dec3e2ca6.ab5d2ec4eca10.2a14.a8dec3eca6.ab6dec5eca25.amdmdm3dec4eca5.a8decn3eca26.5a4cen3eca5.amdmdm3dec5a33.9a7.9a284./103.7a55.2a7b2a8.3a41.a11b2a5.ab2
		+da21.16a2.a14ba3.ab3dea15.5a16ba6c9d2ba2.ab2d2ea12.3a22bc5bc10db2ab3dea6.2a3.2a24bcb5dbc10d2bded2ea5.adea.a9b16dcb7dbc14dea5.adea.a4b21dcb2d4f4dcdgh7ded2ea5.ade2a3b23dcbd
		+7f2dcd2h9dea6.adec2b25dc2d8fdc9ded2ea6.adecb26dc2d7f2dc10d2ea7.adcb27dc2d6f2dec2d3ie3d2ea8.adcb7de19dce2d5f2decdi3j2i3ea9.adc8de19dce3d3f2dec2di2l3j2i2a10.ac9de17dedce7de
		+c3di3l3jaja9.ac9de17dedc2e5dec4eaia2l4ja8.akce29dc2e3d2ec4a3.2a3la10.ace30dc5eca9.3a12.c2e30d5ca26.a2e30d3ea28.a3e25d4e2a30.a6e17d6e2a33.2a25e2a37.2a18c8da31.a8d8c6ac7dec
		+4ea26.a7dec5eca6.a7dec3eca26.a7dec4e2ca6.a6d2ec3eca26.a6d2ec4e2ca6.ab5d2ec2e2ca26.ab5d2ec4e2ca6.ab5d2ec2e2ca26.ab5d2ecec2e2ca6.ab2de2d2ec2e2ca26.ab2de2d2ec2ece2ca6.ab3ded
		+2ec2e2ca26.ab3ded2ec4e2ca6.ab5d2e2ce2ca26.ab5d2ec4e2ca6.ab5d2ec2e2ca26.ab5d2ec4e2ca6.ab5d2ec2e2ca26.ab5d2ec4e2ca6.ab5d2ec2e2ca26.ab5d2ec5eca6.ab6dec2e2ca26.ab6dec6eca5.a8
		+dec2eca26.a8decen3eca5.amdmdm3dec3eca25.amdmdm3dec6a7.4a5cn3eca26.9a19.9a278.
		emberSlime|26|20|17|13|a382019,bD49D6C,cFFFFFF,dCB8A5D,e986348,f291712,g734738,h412820,iE2CD81|idle:0;hop:1;strike:2
		+113.8a16.2a8b2a13.a3b2c5b2d2a10.a2b3c2b8da8.a2b2cb11dea6.a3b14dea6.ab3dfc6dfc3d2ea4.ab4d2f6d2f3d2ea4.ab17d2ea4.a17d2ega4.a7d6h4d2ega4.ae2d2i12d2ega5.a3e12d2ega7.ag14ega9.
		+16a31./10.6a18.2a6b2a15.a3b2c3b2da13.a2b3cb6da12.ab2cb7dea11.a3b9dea11.ab2dfc4dfc2dea10.ab2d2f4d2f2dea10.ab12dea10.a12d2ea10.a5d4h3d2ea10.a2d2i8d2ea10.ae11dega11.ae9d2ega
		+11.a2e8dega13.a10ea15.a8ga17.8a61./140.8a16.2a8b3a11.2a3b2c5b3d2a8.a3b3cb10d2a5.a3b2cb6dfc5dea3.a3b7dfcd2f5dea3.ab9d2f7d2ea2.ab11d7hd2ea2.ab10dhchchc2hdega2.a11d8hdega2.a
		+e2d2i7dhchchc2dega3.a2e16d2ega4.ag17ega6.19a28.
		fish|18|10|8|9|a1B2638,b364D6A,c80AED4,d6799C6,e4A6D90,fFFFFFF,g15111A,hDBC36E,iD8E8F8|idle:0;fly:0,1
		+20.a4.5a7.aba.2a5c2a5.a2ba2c6dc2a3.aeb8dfgdca2.aeb2d2h7dea2.a2bae7ie2a3.aba.2a5e2a6.a4.5a24./25.5a9.a.2a5c2a6.aba2c6dc2a3.abe8dfgdca2.abe2d2h7dea3.abae7ie2a5.a.2a5e2a11.5
		+a24.
		frog|20|13|10|10|a182F22,bFFFFFF,c15111A,d66A85D,e87BC72,f335737,g477A48,hDDE4AE,i32583B|idle:0;hop:1
		+46.2a4.2a11.a2ba2.a2ba9.abcbd2adbcba8.a4d2e4da7.a12da6.ad10fda6.agd8hdga6.a2gda4had2ga6.a2ia.4a.a2ia7.2a8.2a24./8.2a4.2a11.a2ba2.a2ba9.abcbd2adbcba6.2ae3d2e5da5.ae13da3.a
		+g4d8fda3.ag2dagd6hdga4.a2da.agd4a2da5.aia3.aia3.aia6.a5.a5.a65.
		giraffe|40|62|58|12|a231912,b644A34,c38291E,dCFB474,eD9C286,f6D5942,g957F56,h15111A,iFFFFFF,jECDEB5,k473126,l97704A,m7B5A3B,n392C24|idle:0;walk:1,2,3,4;alt:5
		+22.a.a36.ababa35.acac2a33.a2d4e2a30.a7d2e2a28.fg3dhi4dja26.aefg7djka26.aedfg4d4ja26.aedlf4g3ja26.ae3dgf6a27.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2d
		+ga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.fe3dga28.5afel2dgf24.4a5efe3dgf20.a.2a4e2d2l2d5fa19.adf2ed2l3d2l7da19.
		+afe3d2l6d2l4da19.af7d2l3d2l4da19.af2d2l3d2l7dlda19.afgd2l7d2l5da19.afg10d2l4dga19.acf2gd11jdga20.a2cfdldf5gfdld2fga20.3adld4f2afdldfmga22.a2dgfgfa2.a2dgfgfa22.a2dgfgfa2.a
		+2dgfgfa22.adlgfmfa2.adlgfmfa22.a2dgfgfa2.a2dgfgfa22.a2dgfgfa2.a2dgfgfa22.a2dgfgfa2.a2dgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aed
		+gfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.a3nf2na2.a3nf2n
		+a22.a3nf2na2.a3nf2na23.6a4.6a100./22.a.a36.ababa35.acac2a33.a2d4e2a30.a7d2e2a28.fg3dhi4dja26.aefg7djka26.aedfg4d4ja26.aedlf4g3ja26.ae3dgf6a27.ael2dga33.ae3dga33.ae3dga33.
		+aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.fe3dga28.5afel2dgf24.4a5efe3dgf20.a.
		+2a4e2d2l2d5fa19.adf2ed2l3d2l7da19.afe3d2l6d2l4da19.af7d2l3d2l4da19.af2d2l3d2l7dlda19.afgd2l7d2l5da19.afg10d2l4dga19.acf2gd11jdga20.a2c3fdldfgfdldf2gfgmga18.2a.afdldfafdld
		+f3agmga21.af2dga.a2dga2.a2gfa21.af2dga.a2dga2.a2gfa21.afdlga.adlga2.agmfa21.af2dga.a2dga2.a2gfa21.af2dga.a2dga2.a2gfa21.af2dga.a2dga2.a2gfa21.afedga.aedga2.adgfa21.afedga
		+.aedga2.adgfa21.afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.
		+afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.af3na.a3na2.a3na21.af3na.a3na2.a3na22.a2fa3.3a4.3a98./21.ababa35.acac2a33.a2d4e2a30.a7d2e2a28.fg3dhi4dja26.aefg7djka26.aedfg4d
		+4ja26.aedlf4g3ja26.ae3dgf6a27.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga3
		+3.aed2lga33.aed2lga32.fe3dga28.5afel2dgf24.4a5efe3dgf20.a.2a4e2d2l2d5fa19.adf2ed2l3d2l7da19.afe3d2l6d2l4da19.af7d2l3d2l4da19.af2d2l3d2l7dlda19.afgd2l7d2l5da19.afg10d2l4dg
		+a19.acf2gd11jdga20.a2cfa8gfdldfa22.3adld4f2afdldfmga22.adldfgfa2.a2dgfmga22.a2dgfgfa2.a2dgfgfa22.a2dgfmfa2.adlgfgfa22.adlgfgfa2.a2dgfmfa22.a2dgfgfa2.a2dgfgfa22.a2dgfgfa2.
		+a2dgfgfa22.a2dgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.ae
		+dgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgf2na2.a3nfgfa22.a3nf2na2.a3nf2na22.a3nf2a4.2af3na23.3a10.3a100./22.a.a36.ababa35.acac2a33.a2d4
		+e2a30.a7d2e2a28.fg3dhi4dja26.aefg7djka26.aedfg4d4ja26.aedlf4g3ja26.ae3dgf6a27.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga
		+33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.fe3dga28.5afel2dgf24.4a5efe3dgf20.a.2a4e2d2l2d5fa19.adf2ed2l3d2l7da19.afe3d2l6d2l4da19.af7d2l3d2l4da
		+19.af2d2l3d2l7dlda19.afgd2l7d2l5da19.afg10d2l4dga19.acf2gd11jdga20.afdldf9gfdlda21.fdldf2a5fa2fdlda21.a2dga2.a2gfa.af2dga21.a2dga2.a2gfa.af2dga21.adlga2.agmfa.afdlga21.a2
		+dga2.a2gfa.af2dga21.a2dga2.a2gfa.af2dga21.a2dga2.a2gfa.af2dga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedg
		+a21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.a3na2.a3na.af3na21.a3na2.a3na.af3n
		+a22.3a4.3a3.a2fa101./21.ababa35.acac2a33.a2d4e2a30.a7d2e2a28.fg3dhi4dja26.aefg7djka26.aedfg4d4ja26.aedlf4g3ja26.ae3dgf6a27.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32
		+.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.fe3dga28.5afel2dgf24.4a5efe3dgf20.a.2a4e2d2l2d5fa19.adf
		+2ed2l3d2l7da19.afe3d2l6d2l4da19.af7d2l3d2l4da19.af2d2l3d2l7dlda19.afgd2l7d2l5da19.afg10d2l4dga19.acf2gd11jdga20.a2cfdldf10gfga20.3adld4f2afdldfmga22.a2dgfmga2.adldfgfa22.
		+a2dgfgfa2.a2dgfgfa22.adlgfgfa2.a2dgfmfa22.a2dgfmfa2.adlgfgfa22.a2dgfgfa2.a2dgfgfa22.a2dgfgfa2.a2dgfgfa22.aedgfgfa2.a2dgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.ae
		+dgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.a3nf
		+gfa2.aedgf2na22.a3nf2na2.a3nf2na23.2af3na2.a3nf2a27.3a4.3a103./1094.6a29.5a6ea24.4a5e2d2l2d6a15.a.2a4e2d2l3d2l2dfe3dga13.adf2ed2l3d2l7dfed2lga13.afe3d2l6d2l3dfed2lga14.af
		+7d2l3d2l2dfe3dga15.af2d2l3d2l7dfel2dga15.afgd2l7d2l3dfe3dga15.afg10d2l2dfe3dg2a.a13.acf2gd10jfed2lg2ababa12.a2cfdldf5gfdlfed2lg2acac2a12.3adld4f2afdld4f2a2d4e2a12.a2dgfgf
		+a2.a2dgfgf2a7d2e2a10.a2dgfgfa2.a2dgfgf2ag3dhi4dja9.adlgfmfa2.adlgfmfa.ag7djka9.a2dgfgfa2.a2dgfgfa2.ag4d4ja9.a2dgfgfa2.a2dgfgfa3.a4g3ja10.a2dgfgfa2.a2dgfgfa4.7a11.aedgfgfa
		+2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.
		+aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.a3nf2na2.a3nf2na22.a3nf2na2.a3nf2na23.6a4.6a100.
		golem|48|50|45|20|a16141A,b62824B,c839D65,d9C988F,e455C38,f7D7973,g3D3B40,h242227,i2E2C30,j565454,k86DFDA,lE5FAF8,m6DC3BD,nC4F4EE,o252326,p88837B,q5D5A56|idle:0;walk:1,2,3,4;windup:5;strike:6;throw:7
		+832.5a40.3a2b2cb2a36.2a2b2c2b2c2ba34.ad2beb3d2bcbda32.a4d7f4da.5a24.a2d14fdg5da23.ad9f4h2fgd5fda21.a2d5fi2fh4dhgd7fda20.ad7fihd4fdg7ifja20.ad8fh5fjg6fklja20.a9fh5fjg8fja2
		+0.a9fhj3f2jgj2f5ija20.a5fi4fhj4hfg7ja21.a6fi4fh3dhfm5g2a22.aj9fhd3fjh2nmfja24.aj9fh4fjhmnf2ja24.aj9fh4fjh2f3ja24.a2j8f7hf4ja25.a2j7fh5dh3jga26.a3j5fhd5fdhj2ga27.a7jh6fjh2
		+ga29.a4j2gh5fijh2a31.6gh6fjh33.a2fi2fhj4fijh33.a5fjh5jha33.aj4f2j5hga33.ad5fjg4jga33.a6fjg4jga33.a7fjg4jga33.6a2g6a166./832.5a40.3a2b2cb2a36.2a2b2c2b2c2ba34.ad2beb3d2bcbd
		+a32.a4d7f4da.5a24.a2d14fdg5da23.ad9f4h2fgd5fda21.a2d5fi2fh4dhgd7fda20.ad7fihd4fdg7ifja20.ad8fh5fjg6fklja20.a9fh5fjg8fja20.a9fhj3f2jgj2f5ija20.a5fi4fh2j3hfg7ja21.a6fi4f2h3
		+dhm5g2a22.aj10fhd3fjhnmfja24.aj10fh4fjhnf2ja24.aj10fh4fjhf3ja24.a2j9fhj5h4ja25.a2j9fh5dhjga26.a3j7fhd5fdhga27.a9jh6fjha29.a4j3gjh5fijh31.a7gh6fja33.g2fi2fhj4fija33.a5fjh5
		+ja34.aj4f2j3h2a35.ad5fj2ga37.a6fj2ga37.a7fj2ga37.2a6g2a168./880.5a40.3a2b2cb2a36.2a2b2c2b2c2ba34.ad2beb3d2bcbda32.a4d7f4da.5a24.a2d14fdg5da23.ad9f4h2fgd5fda21.a2d5fi2fh4d
		+hgd7fda20.ad7fihd4fdg7ifja20.ad8fh5fjg6fklja20.a9fh5fjg8fja20.a9fhj3f2jgj2f5ija20.a5fi4fhj4hfg7ja21.a6fi4fh3dhfm5g2a22.aj9fhd3fjh2nmfja24.aj9fh4fjhmnf2ja24.aj9fh4fjh2f3ja
		+24.a2j8f7hf4ja25.a2j7fh5dh3jga26.a3j5fhd5fdhj2ga27.a7jh6fjh2ga29.a4j2gh5fijh2a31.6gh6fjh33.a5fhj4fijh33.aj4fjh5jha33.ad5fj5hga33.a6fjg4jga33.a7fjg4jga33.6a2g6a166./832.5a
		+40.3a2b2cb2a36.2a2b2c2b2c2ba34.ad2beb3d2bcbda32.a4d7f4da.5a24.a2d14fdg5da23.ad9f4h2fgd5fda21.a2d5fi2fh4dhgd7fda20.ad7fihd4fdg7ifja20.ad8fh5fjg6fklja20.a9fh5fjg8fja20.a9fh
		+j3f2jgj2f5ija20.a5fi4f4hjhfg7ja21.a6fi3fh3dh2fm5g2a22.aj8fhd3fjhm2nmfja24.aj8fh4fjhfmnf2ja24.aj8fh4fjh3f3ja24.a2j7f5hjh2f4ja25.a2j5fh5dh2f3jga26.a3j3fhd5fdh3j2ga27.a5jh6f
		+jhj3ga28.ag4jh5fijh4g29.af4gh6fjh3ga29.a2fi2fhj4fijh2jga29.a5fjh5jh2j2ga29.aj4f2jha3h3j2ga29.ad5fja.af5jga29.a6fja.a6jga29.a7fj2a7jga29.8a2.8a164./880.5a40.3a2b2cb2a36.2a
		+2b2c2b2c2ba34.ad2beb3d2bcbda32.a4d7f4da.5a24.a2d14fdg5da23.ad9f4h2fgd5fda21.a2d5fi2fh4dhgd7fda20.ad7fihd4fdg7ifja20.ad8fh5fjg6fklja20.a9fh5fjg8fja20.a9fhj3f2jgj2f5ija20.a
		+5fi4fhj4hfg7ja21.a6fi4fh3dhfm5g2a22.aj9fhd3fjh2nmfja24.aj9fh4fjhmnf2ja24.aj9fh4fjh2f3ja24.a2j8f7hf4ja25.a2j7fh5dh3jga26.a3j5fhd5fdhj2ga27.a7jh6fjh2ga29.a4j2gh5fijh2a31.6g
		+h6fjh33.a5fhj4fijh33.aj4fjh5jha33.ad5fj5hga33.a6fjg4jga33.a7fjg4jga33.6a2g6a166./160.5a42.a5fa40.af4j3h2a37.a4jh5da36.a3jhd5fda35.a3jh6fja35.ag2jh5fija36.a2gh6fja37.3hj4f
		+ija36.af2jh5ja37.a4j5h38.a3jhd3fja37.ag2jh4fja37.a3gh4fja35.a2g2bchj2f2ja33.2a2b2c2b2h3jh33.ad2beb2dhdf3hda31.a4d4fh5fjh.5a24.a2d7fh5fjhg5da23.ad8fhj3f2jgd5fda21.a2d5fi3f
		+h4jgd7fda20.ad7fi3f4hg7ifja20.ad8fi6fg6fklja20.a16fg8fja20.a16fgj2f5ija20.a5fi11fg7ja21.a6fi10fm5g2a22.aj15fm2nmfja24.aj16fmnf2ja24.aj18f3ja24.a2j16f4ja25.a2j14f3jga26.a3
		+j11f4j2ga27.a15j3ga29.a4j3g5j3g2a31.15g33.a6fjg4jga33.a2fi3fjgo3jga33.a5f2jg3j2ga33.aj4f2jg3j2ga33.ad5fjg4jga33.a6fjg4jga33.a7fjg4jga33.6a2g6a166./928.5a40.3a2b2cb2a36.2a
		+2b2c2b2c2ba34.ad2beb3d2bcbda32.a4d7f4da.5a24.a2d14fdg5da23.ad15fgd5fda21.a2d5fi6f2hgd7fda20.ad7fi4fh2dg7ifja20.ad8fi2fhd2fg6fklja20.a12fh3fg8fja20.a12fh3fgj2f5ija20.a5fi6
		+fhj3fg7ja21.a6fi6fh3jh6ga22.aj13f4h4fja23.aj16fh4fjh23.aj16fhj2f2jha22.a2j16fh3j4h2a20.a2j14f2j4h5da19.a3j11f4j2ghd5fda19.a15j4gh6fja20.a4j3g5j5gjh5fija21.a13g2a2gh6fja22
		+.aj4f2jgj2ga2.2ahj4fija22.ad5fjg2jga5.a5ja23.a6fjg2jga2.p3.2ap2a3.p20.a7fjg2jga2.p3.p.p3.p22.4a4g4a167./832.5a40.3a2b2cb2a17.4a15.2a2b2c2b2c2ba15.a4pa13.ad2beb3d2bcbda13.
		+a5pqa11.a4d7f4da.5a6.a4p2qa10.a2d14fdg5da6.a4qa11.ad15fgd5fda6.4a11.a2d5fi8fgd7fda20.ad7fi5f2hg7ifjg3a17.ad8fi3fh2dg6fkljg3da16.a12fhd2fg8fjg3fda15.a12fh3fgj2f5ijg3fja15.
		+a5fi6fh4fg7jg3fija15.a6fi5fhj3fj7g5fja15.aj12fh4jhj2fjhj4fija15.aj13f4hnh3j2a5ja16.aj18fj3h2.5a17.a2j16f4ja25.a2j14f3jga26.a3j11f4j2ga27.a15j3ga29.a4j3g5j3g2a31.15g33.a2f
		+i3fjgo3jga33.a5f2jg3j2ga33.aj4f2jg3j2ga33.ad5fjg4jga33.a6fjg4jga33.a7fjg4jga33.6a2g6a166.
		grizzly|50|28|25|18|a181114,bB3A593,c8F755A,d372727,e694F3C,f4B372F,gFFFFFF,h1A1316,iC2AB8D,j1E1519,kAC916F,l786352,m1F1515,nE7DFC9,oEFEAD9,p834248|idle:0;walk:1,2,3,4;strike:5
		+117.8a39.3a8b2a34.3a13b2a28.4a3c14b2da24.2a8c10b2cd3ea21.2a21cde3fe6a14.a4c19ede2f2e6c2a11.a3c17ef4ed2e10ca10.a2c18ef3ed3c4e3f3eca9.ac20efed2c7egh4e2a8.a21efedc8e2h4i2ja7
		+.a22efd11e4k2ja7.af22edf9ef6ka7.af23edf7e2f5la9.af23edf6ef5ma10.a5ed11ed5edfd2f4e2f3ka11.a5ed11fd5e2dfd7f3a12.a4ef13d4efd3f3d4a15.a4ef7d5ad4efd4fda19.a3e2fd3f2da5.a3e2fd3
		+f2da19.a3e2fd3f2da5.a3e2fd3f2da19.a4e2fd3f2da4.a4e2fd3f2da18.a5efd4fda4.a5efd4fda18.adndndndndndna4.adndndndndndna19.12a6.12a67./117.8a39.3a8b2a34.3a13b2a28.4a3c14b2da24.
		+2a8c10b2cd3ea21.2a21cde3fe6a14.a4c19ede2f2e6c2a11.a3c17ef4ed2e10ca10.a2c18ef3ed3c4e3f3eca9.ac20efed2c7egh4e2a8.a21efedc8e2h4i2ja7.a22efd11e4k2ja7.af22edf9ef6ka7.af23edf7e
		+2f5la9.af23edf6ef5ma11.ad5ed7ed5ed3fd2f4e2f3ka13.d5ed7fd5edf3ad7f3a14.a4ef9d4efda2.af5d2a17.a4ef3d5ad4efa3.a4fda19.a3e2f2da5.a3e2fa3.a3f2da19.a3e2f2da5.a3e2fa3.a3f2da19.a
		+4e2f2da4.a4e2fa2.a4f2da18.a5ef2da4.a5efa2.a5fda18.adndndndna4.adndndna2.adndndna19.2a4d2a6.6a4.6a65./67.8a39.3a8b2a34.3a13b2a28.4a3c14b2da24.2a8c10b2cd3ea21.2a21cde3fe6a1
		+4.a4c19ede2f2e6c2a11.a3c17ef4ed2e10ca10.a2c18ef3ed3c4e3f3eca9.ac20efed2c7egh4e2a8.a21efedc8e2h4i2ja7.a22efd11e4k2ja7.af22edf9ef6ka7.af23edf7e2f5la9.af23edf6ef5ma11.a2f14e
		+d5edfd2f4e2f3ka11.a5ed11fd5e2dfd7f3a12.a5e13d4efd3f3d4a15.a4ef7d5ad4efd4fda19.a4efd3f2da5.a3e2fd4fda19.a3e2fd3f2da5.a3e2fd3f2da19.a3e2fd4f2da4.a4e2fd2f2da19.a4e2fd4fda4.a
		+5efd3f2da18.a5efdndndna4.adndndnd4fda18.adndndnd5a6.5a2dndndna19.6a18.6a67./117.8a39.3a8b2a34.3a13b2a28.4a3c14b2da24.2a8c10b2cd3ea21.2a21cde3fe6a14.a4c19ede2f2e6c2a11.a3c
		+17ef4ed2e10ca10.a2c18ef3ed3c4e3f3eca9.ac20efed2c7egh4e2a8.a21efedc8e2h4i2ja7.a22efd11e4k2ja7.af22edf9ef6ka7.af23edf7e2f5la9.af23edf6ef5ma8.a5ed15ed5ed2f4e2f3ka9.a5ed15fd5
		+e2d7f3a10.a4efda15d4ef3d6a13.a4efa.2a7d5ad4ef2da19.a3e2fa3.a3f2da5.a3e2f2da19.a3e2fa3.a3f2da5.a3e2f2da19.a4e2fa2.a4f2da4.a4e2f2da18.a5efa2.a5fda4.a5ef2da18.adndndna2.adnd
		+ndna4.adndndndna19.6a4.6a6.2a4d2a69./67.8a39.3a8b2a34.3a13b2a28.4a3c14b2da24.2a8c10b2cd3ea21.2a21cde3fe6a14.a4c19ede2f2e6c2a11.a3c17ef4ed2e10ca10.a2c18ef3ed3c4e3f3eca9.ac
		+20efed2c7egh4e2a8.a21efedc8e2h4i2ja7.a22efd11e4k2ja7.af22edf9ef6ka7.af23edf7e2f5la9.af23edf6ef5ma10.a5ed16e3fd2f4e2f3ka11.a5ed11fd5e2dfd7f3a12.a4ef13d5ed3f3d4a15.a4ef7d5a
		+d4efd4fda19.a3e2fd4fda5.a4efd3f2da19.a3e2fd3f2da5.a3e2fd3f2da19.a4e2fd2f2da5.a3e2fd4f2da18.a5efd3f2da4.a4e2fd4fda18.adndndnd4fda4.a5efdndndna19.5a2dndndna4.adndndnd5a26.6
		+a6.6a73./117.8a39.3a8b2a34.3a13b2a28.4a3c14bc4a22.2a8c10b4cd3ea19.2a23cde3fe6a12.a4c21ede2f2e6c2a9.a3c17ef6ed2e10ca8.a2c18ef5ed3c4e3f3eca7.ac20ef3ed2c7egh4e2a6.a21ef3edc8
		+e2h4i2ja5.a22ef2ed11e4k2ja5.af24edf9efkokoka6.af25edf7e2f5pa7.af18ed5e2df6e2f5pa6.a5ed14ed5edfdf5e2fkokoka6.a5ed14fd4efd2fd2f3e2f4ka7.a4ef16d4efdfd2a6f3la8.a4ef3a7d5ad3e2
		+fdfda.9a9.a3e2fa2.a3f2da5.a3e2f3da19.a3e2fa2.a4f2da4.a4e2f2da19.a4e2fa.a5fda4.a5ef3da18.a5efa.adndndna4.adndndndfda18.adndndna2.6a6.2a4dndna19.6a18.6a68.
		imp|34|34|31|13.5|a17191E,b381E1E,c251414,dC4826C,eB76659,f5A3834,g804A43,h1A1418,iD9C769,j381E26,kE7E2C9,l7D5C57,m562D2F,n3C2128,o2B1A23,p2A242C,q6F4F58,r472428,s321A20,t23141A,u494048,v3A3238,w1E1A20|idle:0;walk:1,2,3,4;windup:5;strike:6;shoot:5
		+12.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac4d4ea23.ac3e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.
		+al3mf4m2n5ega15.a4mf3nof2g2ega2ga12.a.an4m4f.5ag2a12.ap2a2n4m2na6.a13.aega.a2n3mnoa19.aega2.onomnmoa19.aega2.a3on3oa19.a2e2a.aqor2oso21.aegp2a6tsta20.3a.aq2rst2sta24.aq2r
		+st2sta25.a2rst2sta25.a2rst2sta25.ar2sts2ta25.aeg2agfa26.aeg2agfa25.a4ut3va24.a4upt2vwa24.4at4a50./12.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac4d4ea23.ac3e4fea23.acg2e2hih
		+2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga12.a.an4m4f.5ag2a12.ap2a2n4m2na6.a13.ae
		+ga.a2n3mnoa19.aega2.onomnmoa19.aega2.a3on3oa19.a2e2a.aqor2oso21.aegp2a6tsta20.3a.a2q2rststa25.aq2rs2ta27.a2r2sta27.tq2rst28.at2rsa28.atega29.ateg2a28.at4ua27.at3upa28.a3t
		+a52./46.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac4d4ea23.ac3e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3de
		+fa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga12.a.an4m4f.5ag2a12.ap2a2n4m2na6.a13.aega.a2n3mnoa19.aega2.onomnmoa19.aega2.a3on3oa19.a2e2a.tqor2osota19.aegp2a6tsta20.3a.aq2rstrsta
		+25.a2rstr2sta24.a2rs2a2sta24.ar2s2agfta24.aega.agfa25.aeg2a3va24.a4ut3vwa23.a4upt3a25.5a54./12.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac4d4ea23.ac3e4fea23.acg2e2hih2ea22.
		+a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga12.a.an4m4f.5ag2a12.ap2a2n4m2na6.a13.aega.a2n
		+3mnoa19.aega2.onomnmoa19.aega2.a3on3oa19.a2e2a.aqor2oso21.aegp2a6tsta20.3a.aq2rstr2sta22.aq2rs2ar2sta22.a2r2sa.a2s2ta20.aq2rsa2.ar2sta20.a2rsa4.a2sta20.aega5.agfa21.aega5
		+.agf2a20.a3ua4.a4va19.a3upa3.a3vwa20.4a5.4a48./46.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac4d4ea23.ac3e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2
		+a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga12.a.an4m4f.5ag2a12.ap2a2n4m2na6.a13.aega.a2n3mnoa19.aega2.onomnmoa19.aega2.a3on3oa19.a2e2
		+a.tqor2osota19.aegp2a6tsta20.3a.a2qrst2sta25.aq2rststa26.a2rststa26.aegs3ta26.aegtgfa26.a3utgfa26.a3upt2va26.2a2t3vwa28.5a50./11.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac
		+4d4ea23.ac3e4fef.a21.acg2e2hih2e2fa20.a2g7e2f2a21.ag2ejkj2fdeaga20.f2gej2fd2e2ga20.2o4flm2eg2a20.a2l2f2lmnfga21.a2lf2l2mnf2a21.a2lmfm2nofa23.al3m4fna23.a7m2na22.2an5m2na2
		+2.apo2n4m2na21.aeg2a2n3mnoa20.aega.anomnmoa20.aega2.3on4o20.a2e2a.aor2osoa21.aegp2a6tsta20.3a.aq2rst2sta24.aq2rststa26.a2rs3ta26.a2rs2ta27.ar2sta28.aegta29.aegta28.a4uta2
		+7.a4upta27.2a3ta53./48.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac4d4ea23.ac3e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ekjkjka24.a2ge5ja22.2af2ge5ja21.a3l2fgkjk2ga20.a2l3m6fa20.a
		+2l3m7f21.al3mf2lm2f2ea.a18.a4mf3mne3fafa14.a2.an3mf3no2e2d3f13.apa.a2n3m3f2g3edfga11.aega2.a2n3mnofa2g2e2ga10.aega2.aonomnmoa2.2agaga10.aega2.aq3on3oa4.a.a11.a2e2a.tqror2
		+otoa19.aegp2a6tsta20.3a2.aq2rs2ta27.a2r2sta27.tq2rst28.at2rsa28.atega29.ateg2a28.at4ua27.at3upa28.a3ta52.
		mimic|22|22|18|11|a291F18,bC5A374,cA9895F,d856A46,e898D96,fD3BD68,gECE0A2,h685137,iD9C769,j15111A,kFFFFFF,l462026,m70333B,nD17985|idle:0;hop:1,2;strike:3
		+202.14a7.a14ba6.a14ca6.a14da6.a6e2f6ea6.a6cfg6ca6.a14ca6.acd10cdca6.a14ca6.a14ha7.14a48./92.14a7.a14ba6.a2cij6cij2ca6.a14da6.aka2ka2ka2ka2k2a6.al12mla6.al4m5n3mla6.al4m5n
		+3mla6.2ak2ak2ak2ak2aka6.a6e2f6ea6.a6cfg6ca6.a14ca6.acd10cdca6.a14ca6.a14ha7.14a48./48.14a7.a14ba6.a2cij6cij2ca6.a14da6.aka2ka2ka2ka2k2a6.al12mla6.al12mla6.al12mla6.al4m5n
		+3mla6.al4m5n3mla6.2ak2ak2ak2ak2aka6.a6e2f6ea6.a6cfg6ca6.a14ca6.acd10cdca6.a14ca6.a14ha7.14a48./114.14a7.a14ba6.a2cij6cij2ca6.a14da6.aka2ka2ka2ka2k2a6.al12m2a6.al11ma2na5.
		+2ak2ak2ak2ak2a3na4.a6e2f5ea2na4.a6cfg6c2a5.a14ca6.acd10cdca6.a14ca6.a14ha7.14a48.
		pig|30|18|16|11.5|a38202A,bE29DA7,cF2C4BD,d9C5D74,eC47C8E,f1E1519,gFFFFFF,hF0B4B4,i83495D,j5A3644|idle:0;walk:1,2,3,4;alt:5
		+48.2a17.9a.a2ba14.2a9cdbe2b3a10.a11cdbeb4ca7.2a2c10bd8ca5.aea11bd2c3bfg2b3a2.aeae11bdc4b2f2b3ha.ae2a11bd8b2hiha2.a2e11bde7b4ha3.2ae11bde5bd2hiha4.a2e10bed2e4b2d2a6.d3bd3e
		+d3b3d5e2a8.a3b5d3b2ded4a10.a2be5d2bededa14.a2beded2a2bededa14.a3jd2j2a3jd2ja15.6a2.6a11./48.2a17.9a.a2ba14.2a9cdbe2b3a10.a11cdbeb4ca7.2a2c10bd8ca5.aea11bd2c3bfg2b3a2.aeae
		+11bdc4b2f2b3ha.ae2a11bd8b2hiha2.a2e11bde7b4ha3.2ae11bde5bd2hiha4.a2e10bed2e4b2d2a6.aed3bd3bd2e2d5e2a9.2d3bd3b4de3d2a11.ad2bed2bed3a2eda13.ad2bed2bea2.a2eda13.ad3jd3ja2.a3
		+ja14.a2da.3a4.3a9./18.2a17.9a.a2ba14.2a9cdbe2b3a10.a11cdbeb4ca7.2a2c10bd8ca5.aea11bd2c3bfg2b3a2.aeae11bdc4b2f2b3ha.ae2a11bd8b2hiha2.a2e11bde7b4ha3.2ae11bde5bd2hiha4.a2e10
		+bed2e4b2d2a6.a7ed3b3d5e2a8.a3b5d3b2ded4a10.a3b5d2bed2ea14.a2beded2a2bededa14.a2bed2j2a3jdeda14.a3jd2a2.2ad3ja15.3a8.3a11./48.2a17.9a.a2ba14.2a9cdbe2b3a10.a11cdbeb4ca7.2a2
		+c10bd8ca5.aea11bd2c3bfg2b3a2.aeae11bdc4b2f2b3ha.ae2a11bd8b2hiha2.a2e11bde7b4ha3.2ae11bde5bd2hiha4.a2e10bed2e4b2d2a4.a3bd7ed3bd5e2a6.a3b9d3b6a8.a2bed2a6d2bea13.a2bea2.a2e3
		+d2bea13.a3ja2.a3j2d3ja14.3a4.3a.a2da12./18.2a17.9a.a2ba14.2a9cdbe2b3a10.a11cdbeb4ca7.2a2c10bd8ca5.aea11bd2c3bfg2b3a2.aeae11bdc4b2f2b3ha.ae2a11bd8b2hiha2.a2e11bde7b4ha3.2a
		+e11bde5bd2hiha4.a2e10bed2e4b2d2a6.d3bd8e2d5e2a8.a3b5d3b2ded4a10.a2be5d3bdeda14.a2beded2a2bededa14.a3jded2a2bed2ja15.2ad3j2a3jd2a19.3a2.3a14./67.9a19.2a9c2a16.a13ca13.2a2c
		+13bda10.aea14bd2ba8.aeae13bdbe2b3a5.ae2a13bdbeb4ca5.a2e13bd8ca5.2ae11bd2c3bfg2b3a4.a2e10bdc4b2f2b3ha4.d3bd3ed3bd8b2hiha4.a3b5d3bde7b4ha4.a2be5d2be2de5bd2hiha4.a2beded2a2b
		+eded2e4b2d2a5.a3jd2j2a3jd2jd5e2a8.6a2.6a.5a5.
		pirate|32|38|33|16|a7D6153,bAF7B72,c9A605D,d15131A,e704546,f503236,g18151D,h14121A,iB59378,jA17962,k825F4E,lE5DCC5,m676162,nDFD8C5,oB1756A,p4C2A2E,q99524E,r6C3A3B,s969189,t392C24,u8F7E68,v352B2C,w8C7245,x675545,yC5A766,zE6EAF0,AA6AEBB,B4A3C35,CCCAB8E,D2A2124,E645A52,F221A21,G1C1620,HE6EBF5|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7
		+109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c2ge2ah17.defae3ce2a2gih17.def2a3ea2i2gih18.deai3aj5ih19.d.h9ih22.h7ijh23.h6jh24.h5kh24.hl3mknm23.hopoqrpqrp22.hlm2nsm2sm22.hqp
		+2qrp2rp22.hnmn2sm2sm22.hrpoqrpr2p22.hsmlnsms2m22.hrp2qrpt2p23.3mij3mh22.hu2v2pwdv23.hu2xdyzAd23.hu2xBdzAd24.huxBdAzd24.huxBvdzAd23.h2xBvdAzd23.hCijvjdAd23.hCijvjkd23.hD2E
		+FvDGh23.h4DFvFGh23.3h2v3h108./109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c2ge2ah17.defae3ce2a2gih17.def2a3ea2i2gih18.deai3aj5ih19.d.h9ih22.h7ijh23.h6jh24.h5kh24.h3m2knmh2
		+2.hpoqrp2qrph21.m2n2smn2smh20.hoq2rp2q2rph20.hlnsm3n2smh20.p2qrp3qr2ph20.mijm4ns2mh21.2pwdty2t2ph21.dyzAd4mkh21.hdzAd4vh22.hdAzdB2vh24.hdzAdvh26.dAzdBv25.hvdAdBh25.hxvdxB
		+h25.hivCijh25.hivCijh25.hFvD2EFh24.hFv3DFh25.2h2v2h109./141.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c2ge2ah17.defae3ce2a2gih17.def2a3ea2i2gih18.deai3aj5ih19.d.h9ih22.h7ijh
		+23.h6jh24.h5kh24.hl3mknm23.hopoqrpqrp22.hlm2nsm2sm22.hqp2qrp2rp22.hnmn2sm2sm22.hrpoqrpr2p22.hsmlnsms2m22.hrp2qrpt2p22.h3mij3mh22.hu2v2pwdv23.hu2xdyzAdh23.huxBdzAdh23.huxB
		+dAzdh23.h2xBvdzAd23.hCijvdAzd23.hCijvDdAd22.hD2EFv2Fdh22.h4DFv2h24.5h111./109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c2ge2ah17.defae3ce2a2gih17.def2a3ea2i2gih18.deai3aj5i
		+h19.d.h9ih22.h7ijh23.h6jh24.h5kh24.hl3mknh23.hopoqrpqrh22.hlm2n2smsh22.h2qpqrorph22.h3nml2nsm22.hr3qpoqrp22.hs4nmijm22.hr3tyt2pwd22.6mdyzAd20.hu6vdzAd20.hu2xBv2BdAzd19.hu
		+2xBvx2BvdzAd18.hux2B2hxBvdAzd17.hu2xBh.hx2BvdAd17.huxBh3.hxBvhd18.hCijh3.hijkh19.hCijh3.hijkh19.hD2EFh2.hF2DGh18.h3DFh2.h3FGh19.4h4.4h106./141.6a25.a4b2ca22.da2b6ca20.d2e
		+8cea18.defe4c2ge2ah17.defae3ce2a2gih17.def2a3ea2i2gih18.deai3aj5ih19.d.h9ih22.h7ijh23.h6jh24.h5kh24.hl3mknm23.hopoqrpqrp22.hlm2nsm2sm22.hqp2qrp2rp22.hnmn2sm2sm22.hrpoqrpr
		+2p22.hsmlnsms2m22.hrp2qrpt2p22.h3mij3mh22.hu2v2pwdv23.h2uxdyzAd24.hu2xdzAd25.huxdAzd25.huxBdzAd24.hCijdAzd23.hD2EFvdAd23.h3DFvGd25.h3v2FGh26.5h108./108.6a25.a4b2ca22.da2b
		+6ca20.d2e8cea18.defe4c2ge2ah16.2defae3ce2a2gih15.dzaef2a3ea2i2gih15.dAzaeai3aj5ih16.dAza.h9ih17.dAz2dh7ijh18.dAz2mh6jh20.dpijp5kh21.hlnsml3knm20.hoq2rp5qrp19.hn2sm5n2sm19
		+.h2qrp5q2rp20.2hm6n2sm22.hr5qr2p22.hs5ns2m22.hr3ty2t2p23.h7mv23.hu6vh23.hu2xBvBvh23.hu2xB2vh25.huxB2vh25.vuxBvh26.v2xBv27.vCijv27.vCijv26.hD2EFvh25.h4DFv26.h4v111./142.6a
		+25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c2ge2ah17.defae3ce2a2gih17.def2a3ea2i2gih18.deai3aj5ih19.d.h9ih22.h7ijk3H20.h6jh4.3H16.h5k2h8.2H13.h2l3mnm3.d7.H11.h2opoqr3ph2p8d11.h
		+lnm2ns2l2nijm7z11.h3qp2r2q2r2jp7A11.h4n5mh2m8d11.hr5qr2p2.d19.hs5ns2m22.hr3ty2t2p22.h8mh22.hu7v24.hu2xBvh26.vux2Bv25.hvu2xBh25.hxvuxBh25.hivCijh25.hivCijh25.hFvD2EFh24.hF
		+v3DFh25.2h2v2h109./109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c2ge2ah2.2d13.defae3ce2a2gih.dzAd12.def2a3ea2i2gihdzAd14.deai3aj5idzAd16.d.h8idzAd20.h6i2pyd22.h4jmijmd22.hk
		+3poqrp22.hlmlnsnsh22.h2op2qr3p22.hl2nm2smsm22.h4q2p2rp22.h6n2sm22.hr5qr2p22.hs5ns2m22.hr3ty2t2p23.8mh22.hu7v23.hu2xBvBvh23.hu2xBvBvh24.huxBvBvh24.huxBvBvh24.h2xBvBvh24.hC
		+ijvjkh24.hCijvjkh23.hD2EFvDGh23.h4DFvFGh23.3h2v3h108.
		pirateCaptain|32|38|33|16|a15131A,b666162,c2C2C38,dB4A071,e7D6153,f14121A,g483429,hA17962,iB59378,j0B0B12,k291E20,l825F4E,mA96D65,n46262C,o8D4747,p633337,q442B30,r855151,s5F3A3E,t1F1D2A,u696465,v8C7245,w2F2F3D,xC5A766,yE6EAF0,zA6AEBB,A252430,B1E1A20,C5C554F,D1A161F,E18141E,FA0716A,GE6EBF5|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7
		+13.5a25.2a5b2a21.2a2b6cba.a17.ada10cada16.ad12cda17.a12da19.12e20.f8g2hf20.f6gihjif20.f4gh3i2ef20.f2gi2h2ie2ke21.fg3i2e4ka21.f2ie6ka22.f2he4ka23.f3le2ka23.fm3nl2e23.fmnmo
		+pnopn22.fmn2opn2pn22.fon2opn2pn22.fono2pn2pn22.fpnmopnp2n22.fpnmopnp2n22.npn2opn2qn21.ar3nihnrsq21.atu2t2nvasa21.atu2waxyz2a21.atu2wAayz2a21.artuwAazya22.astuwAtayza22.at
		+2wAtazya23.fuwAtAaza23.fuwAtAta23.fB2CDtBEf23.f4BDtDEf23.3f2t3f108./13.5a25.2a5b2a21.2a2b6cba.a17.ada10cada16.ad12cda17.a12da19.12e20.f8g2hf20.f6gihjif20.f4gh3i2ef20.f2gi
		+2h2ie2ke21.fg3i2e4ka21.f2ie6ka22.f2he4ka23.f3le2ka23.f3n2l2ef22.fnmopn2opnf21.n2o2pno2pnf20.fmo2pn2o2pnf20.fmopn3o2pnf20.n2opn3op2nf20.nihn4op2nf21.2nva2o3qnf20.2axyzaqFr
		+sqf20.atayzaq2rsq21.atazyaq2rsa21.artayzarsqa21.arsazya2qa22.as2tazaAf24.atwtawAf25.fwtuwAf25.fwtuwAf25.fDtB2CDf24.fDt3BDf25.2f2t2f109./45.5a25.2a5b2a21.2a2b6cba.a17.ada1
		+0cada16.ad12cda17.a12da19.12e20.f8g2hf20.f6gihjif20.f4gh3i2ef20.f2gi2h2ie2ke21.fg3i2e4ka21.f2ie6ka22.f2he4ka23.f3le2ka23.fm3nl2e23.fmnmopnopn22.fmn2opn2pn22.fon2opn2pn22.
		+fono2pn2pn22.fpnmopnp2n22.fpnmopnp2n22.npn2opn2qn21.at3nihnrsq21.atu2t2nvasa21.atu2waxyzaq21.artuwAayzaq21.artuwAazyaf21.ast2wAtayza22.atuwAtazya23.fuwAtBaza22.fB2CDt2Daf
		+22.f4BDt2f24.5f111./13.5a25.2a5b2a21.2a2b6cba.a17.ada10cada16.ad12cda17.a12da19.12e20.f8g2hf20.f6gihjif20.f4gh3i2ef20.f2gi2h2ie2ke21.fg3i2e4ka21.f2ie6ka22.f2he4ka23.f3le2
		+ka23.fm3nl2e23.fmnmopnopf22.fmn2o2pnpf22.f2onopmpnf22.f3onm2opn22.fp3onmopn22.fp4onihn22.n2p3oq2nva20.ar4nqFaxyza19.atu3tq2rayza19.atu2wAq2razya19.tu2wAtqrsqayza18.tuw2A2
		+f3qazya17.fu2wAf.fw2Ataza17.fuwAf3.fwAtfa18.fuwAf3.fwAtf19.fuwAf3.fwAtf19.fB2CDf2.fD2BEf18.f3BDf2.f3DEf19.4f4.4f106./45.5a25.2a5b2a21.2a2b6cba.a17.ada10cada16.ad12cda17.a
		+12da19.12e20.f8g2hf20.f6gihjif20.f4gh3i2ef20.f2gi2h2ie2ke21.fg3i2e4ka21.f2ie6ka22.f2he4ka23.f3le2ka23.fm3nl2e23.fmnmopnopn22.fmn2opn2pn22.fon2opn2pn22.fono2pn2pn22.fpnmop
		+np2n22.fpnmopnp2n22.npn2opn2qn21.at3nihnrsq21.atu2t2nvasa21.at2uwaxyz2a21.artu2wayz2a21.arstuwazya22.asqtuwAayza22.2afuwAazya23.fB2CDtaza23.f3BDtEa25.f3t2DEf26.5f108./12.
		+5a25.2a5b2a21.2a2b6cba.a17.ada10cada16.ad12cda17.a12da19.12e20.f8g2hf16.a3.f6gihjif15.aya2.f4gh3i2ef15.azya.f2gi2h2ie2ke16.azya.fg3i2e4ka16.azy2af2ie6ka17.azy2nf2he4ka19.
		+anihn3le2ka20.fmopnm3l2e20.fmo2pn5opn19.fo2pn5o2pn19.f2opn5o2pn20.2fn6o2pn22.fp5op2n22.fp5op2n22.n2p3o3qn21.ar4nqFrsq21.artu2tq2rsq21.artu2wq2rsq21.artu2wqrsqa21.arstuwA3
		+q22.asqtuwAtf24.2at2wAt27.tuwAt27.tuwAt26.fB2CDtf25.f4BDt26.f4t111./46.5a25.2a5b2a21.2a2b6cba.a17.ada10cada16.ad12cda17.a12da19.12e20.f8g2hf20.f6gihjif20.f4gh3i2ef20.f2gi
		+2h2ie2ke21.fg3i2e4ka21.f2ie6ke2G20.f2he4ka3.3G16.f4le2ka7.2G13.f2m3noea2.a7.G11.f2mnmop3nf2n8a11.fmon2op2m2oihn7y11.f3on2p2o2p2hn7z11.f4o5nf2n8a11.fp5op2n2.a19.fp5op2n22.
		+n2p3o3qn21.at4nqFrsq21.atu3tq2rsa21.artu2wq2rsa21.arstuwqrsqa21.ar2tu2w2qa22.astwtuwAf24.atwtuwAf25.fwtuwAf25.fDtB2CDf24.fDt3BDf25.2f2t2f109./13.5a25.2a5b2a21.2a2b6cba.a1
		+7.ada10cada16.ad12cda17.a12da19.12e20.f8g2hf2.2a16.f6gihjif.ayza15.f4gh3i2efayza16.f2gi2h2ie2kayza18.fg3i2e2kayza20.f2ie3k2nxa22.f2heknihna22.fl3nmopn22.fmnmopopf22.f2mn2
		+op3n22.fm2on2pnpn22.f4o2n2pn22.f6o2pn22.fp5op2n22.fp5op2n22.n2p3o3qn21.ar4nqFrsq21.atu3tq2rsa21.atu2wAq2rsa21.atu2wAqrsqa21.artuwAt3q22.astuwAtAtf23.at2wAtAtf24.fuwAtAtf2
		+4.fuwAtAtf23.fB2CDtBEf23.f4BDtDEf23.3f2t3f108.
		pirateGunner|32|38|33|16|a7D6153,b6C798E,c495A77,d15131A,e374258,f2B3043,g14121A,h0B0B12,iB59378,jA17962,k291E20,l825F4E,m7688A4,n2D364F,o516994,p3B4A6B,q392C24,r847663,s2F2629,t4A4E57,u584A3D,v3F3530,w2A2C34,x2A2124,y645A52,z221A21,A1C1620,BC5A766,CECE2A2,DD9AB69,EC47758|idle:0;walk:1,2,3,4;shoot:5;fire:6;strike:6
		+109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c3e2ag17.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3kg22.g7ijg23.g6jg24.g5lg24.gm3nlon23.gmnmopnopn22.gmn2opn2pn22.gon2
		+opn2pn22.gono2pn2pn22.gpnmopnp2n22.gpnmopnp2n22.gpn2opnq2n23.3nij3ng22.gr2s2ntds23.gr2ud2tdg23.gr2uvdtdg24.gruvdwdg24.gruvsdsg24.g2uvsvsg24.gruvsvsg24.gruvsvsg23.gx2yzsxA
		+g23.g4xzszAg23.3g2s3g108./109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c3e2ag17.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3kg22.g7ijg23.g6jg24.g5lg24.g3n2long22.gnm
		+opn2opng21.n2o2pno2png20.gmo2pn2o2png20.gmopn3o2png20.g2opn3op2ng20.nijn4op2ng21.2ntdqB2q2ng21.d2td5nlg21.gdtd5sg22.gdwduv2sg24.gd2uvsg26.sru2vs25.gsr2uvg25.gusruvg25.gus
		+ruvg25.gusruvg25.gzsx2yzg24.gzs3xzg25.2g2s2g109./141.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c3e2ag17.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3kg22.g7ijg23.g6jg2
		+4.g5lg24.gm3nlon23.gmnmopnopn22.gmn2opn2pn22.gon2opn2pn22.gono2pn2pn22.gpnmopnp2n22.gpnmopnp2n22.gpn2opnq2n22.g3nij3ng22.gr2s2ntds23.gr2ud2tdsg23.gruvdtdsg23.gruvdwdsg23.
		+g2uvsdvsg23.gruvsuvsg23.gruvs2xAg22.gx2yzs2zAg22.g4xzs2g24.5g111./109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c3e2ag17.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3k
		+g22.g7ijg23.g6jg24.g5lg24.gm3nlog23.gmnmopnopg22.gmn2o2pnpg22.g2onopmpng22.g3onm2opn22.gp3onmopn22.gp4onijn22.gp3qBq2ntd22.6nd2td21.gr6sdtd21.gr2uvs2vdwd20.gr2uvsu2vsd21.
		+gru2v2guv2sg19.gr2uvg.gu2vsg19.gruvg3.guvsg19.gruvg3.guvsg19.gruvg3.guvsg19.gx2yzg2.gz2xAg18.g3xzg2.g3zAg19.4g4.4g106./141.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c3e2ag17
		+.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3kg22.g7ijg23.g6jg24.g5lg24.gm3nlon23.gmnmopnopn22.gmn2opn2pn22.gon2opn2pn22.gono2pn2pn22.gpnmopnp2n22.gpnmopnp2n22.gpn
		+2opnq2n22.g3nij3ng22.gr2s2ntds23.g2rud2tdg24.gr2udtdg25.grudwdg25.gruvdsg25.gruv2sg24.gx2yz2sg24.g3xzsAg25.g3s2zAg26.5g108./109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c3e
		+2ag17.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3kg22.g7ijg23.g6jg24.g6l24.g2m3non3g6d14.g2mnmop6n4twd13.gmon2op2m2oijnt3d14.g3on2p2o2p2jnd17.g4o5ng2nd18.gp5opng2
		+2.gp5opng22.gp3qB2qng23.8n23.gr6sg23.gr2uvsvsg23.gr2uv2sg25.gruv2sg25.sruvsg26.s2uvs27.sruvs27.sruvs26.gx2yzsg25.g4xzs26.g4s111./108.6a25.a4b2ca22.da2b6ca20.d2e8cea18.def
		+e4c3e2ag17.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3kg22.g7ijg23.g6jg24.g6l24.g2m3non3g6d.C12.g2mnmop6n4tw2CD11.gmon2op2m2oijnt3dDCE11.g3on2p2o2p2jnd4.D12.g4o5n
		+g2nd18.gp5opng22.gp5opng22.gp3qB2q2n23.g7ng23.gr6sg23.gr2uvsvsg23.gr2uv2sg25.gruv2sg25.sruvsg26.s2uvs27.sruvs27.sruvs26.gx2yzsg25.g4xzs26.g4s111.
		player|32|38|33|16|a14121A,bCCAB8E,cB59378,dA17962,e0B0B12,f825F4E,gF0F002,hF0F001,iF0F003,jF0F004,k6A4242|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+109.6a25.a6ba23.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda23.a6da24.a5fa24.ab4fcf23.abfbcdfcdf22.abf2cdfcdf22.acf2cdf2df22.acfc2df2df
		+22.adfbcdfc2f22.adfbcdfc2f22.adf2cd4f23.3fcd3fa22.ab7f23.ab2cdfdfa23.ab2cdfdfa24.abcdfdfa24.abcdfdfa24.a2cdfdfa24.abcdfdfa24.abcdfdfa23.ag2hifgja23.a4gifija23.3a2f3a108./
		+109.6a25.a6ba23.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda23.a6da24.a5fa24.a5fcfa22.afbcdf2cdfa21.f2c2df2cdfa20.abc2df2c2dfa20.abcdf3
		+c2dfa20.a2cdf4c2fa20.acdf5c2fa21.2fd4c3fa22.9fa21.ab7fa22.a2b2cd2fa24.ab2cdfa26.fbc2df25.afb2cda25.acfbcda25.acfbcda25.acfbcda25.aifg2hia24.aif3gia25.2a2f2a109./141.6a25.
		+a6ba23.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda23.a6da24.a5fa24.ab4fcf23.abfbcdfcdf22.abf2cdfcdf22.acf2cdf2df22.acfc2df2df22.adfbcd
		+fc2f22.adfbcdfc2f22.adf2cd4f22.a3fcd3fa22.ab7f23.ab2cdf2dfa23.abcdf2dfa23.abcdfcdfa23.a2cdfcdfa23.abcdfcdfa23.abcdf2gja22.ag2hif2ija22.a4gif2a24.5a111./109.6a25.a6ba23.a4
		+b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda23.a6da24.a5fa24.ab4fca23.abfbcdfcda22.abf2c2dfda22.a2cfcdbdfa22.a3cfb2cdf22.ad3cfbcdf22.ad4c
		+fcdf22.a2d4c2fa23.8f23.ab6fa23.ab2cdf2dfa21.ab2cdfc2dfa21.abc2d2acd2fa19.ab2cda.ac2dfa19.abcda3.acdfa19.abcda3.acdfa19.abcda3.acdfa19.ag2hia2.ai2gja18.a3gia2.a3ija19.4a4.
		+4a106./141.6a25.a6ba23.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda23.a6da24.a5fa24.ab4fcf23.abfbcdfcdf22.abf2cdfcdf22.acf2cdf2df22.acf
		+c2df2df22.adfbcdfc2f22.adfbcdfc2f22.adf2cd4f22.a3fcd3fa22.ab7f23.a2b2cd2fa24.ab2cd2fa25.abcd2fa25.abcd2fa25.abcd2fa24.ag2hi2fa24.a3gifja25.a3f2ija26.5a108./108.6a25.a6ba2
		+3.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda21.3a6da21.acd6fa21.abcdfc3fcf20.abc2df5cdf19.ac2df6cdf19.a2cdf5c2df20.2af6c2df22.ad6c2f2
		+2.ad6c2f22.a2d4c3f23.a8f23.ab6fa23.ab2cdfdfa23.ab2cd2fa25.abcd2fa25.fbcdfa26.f2cdf27.fbcdf27.fbcdf26.ag2hifa25.a4gif26.a4f111./142.6a25.a6ba23.a4b4ca21.a2b8ca20.ab7c2da20
		+.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda23.a6da23.a5f2a23.abc3fcf23.abcfbcd3f3a19.abcf2cd2b3cda18.a3cf2d2c4da18.a4c5f3a19.ad6c2f22.ad6c2f22.a2d4c3f22.a8fa22.a
		+b7f24.ab2cdfa26.fbc2df25.afb2cda25.acfbcda25.acfbcda25.acfbcda25.aifg2hia24.aif3gia25.2a2f2a109./109.6a25.a6ba23.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a
		+3c2d5ca21.a9ca22.a6c2fa23.a4dfcda23.a4fbcda22.abfbcdcda22.abcf2cd3f22.ab2cf2dfdf22.a4c2f2df22.a6c2df22.ad6c2f22.ad6c2f22.a2d4c3f23.8fa22.ab7f23.ab2cdfdfa23.ab2cdfdfa24.ab
		+cdfdfa24.abcdfdfa24.a2cdfdfa24.abcdfdfa24.abcdfdfa23.ag2hifgja23.a4gifija23.3a2f3a108./109.6a25.a6ba23.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.
		+a9ca22.a7cda23.a6da24.a6f24.abc3fcf6a17.abcfbcd6fdfa16.abcf2cd2b3cd2fa16.a3cf2d2c4dfa17.a4c5f3a19.ad6cfa22.ad6cfa22.a2d4c2fa23.8f23.ab6fa23.ab2cdfdfa23.ab2cd2fa25.abcd2fa
		+25.fbcdfa26.f2cdf27.fbcdf27.fbcdf26.ag2hifa25.a4gif26.a4f111./108.8a23.a8ba21.a4b6ca20.ab9ca20.ab9ca20.ad8cda20.adce4cecda20.adce4cecda20.a10ca20.ad3c2k3cda21.ad6cda22.a8
		+fa20.2ab9c2a17.ab11c2da16.ab11c2da16.ab11cdba16.ab11cdba16.ab10cdbca16.abcd7c2dbca16.a2c10dcda16.acd10acda16.acdfb6cbfcda17.af2b2c2d2c2bfa19.a2bcd2adc2ba20.a2bcd2adc2ba20
		+.a2bcd2adc2ba20.ab2cd2ad2cba20.a2bcd2adc2ba20.a2bcd2adc2ba20.a2hgi2ai2gha20.a3gi2ai3ga21.4a2.4a107.
		player_hair_0|32|38|33|16|aF00001,bF00002|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+141.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b851./141.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b851./173.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b819./141.6a25.a7b23.10b22.8b24.6b2
		+6.4b28.2b31.b851./173.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b819./140.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b852./174.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b818./141.6a25.a7
		+b23.10b22.8b24.6b26.4b28.2b31.b851./141.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b851./140.8a23.a9b22.10b22.b8.b22.b8.b939.
		player_hair_1|32|38|33|16|a14121A,bF00001,cF00002,dF00003|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+12.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c883./12.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6
		+cd25.5c27.3c29.2c883./44.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c851./12.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a1
		+0ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c883./44.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c851./11.a3.a26.aba.aba.a22.abcbabc2
		+aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c884./45.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c850./12.a3.a2
		+6.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c883./12.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c2
		+7.3c29.2c883./11.a3.a3.a22.aba.aba.aba21.acbabcbabcba20.a2cb3cb3ca19.ab10cba18.a12ca20.c8.c1003.
		player_hair_2|32|38|33|16|aF00001,bF00002,c14121A,dF00003,e825F4E|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+141.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.c2bde27.cb2de28.cde30.e660./141.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.
		+c2bde27.cb2d29.cd692./173.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.c2bde27.cb2de28.cde30.e628./141.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.
		+c3bd27.c3bd27.c2b2d27.c2bde27.cb2de28.cde30.e660./173.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.c2bde27.cb2de28.cde30.e628./140.6a25.a7b23.10b20.
		+c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.cb2ed27.ce30.e727./174.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.c2bd28.cb2de28.ede30.e627./141.6a25.a7
		+b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.c2bde27.cb2de28.cde30.e660./141.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.c2bde27.cb2
		+de28.cde30.e660./140.8a23.a9b22.10b20.c12bc18.c2b8.2bc18.c2b8.2bc18.c2b8.2bc18.cbd8.dbc18.cbd8.dbc18.cd10.dc19.c10.c746.
		player_hair_3|32|38|33|16|aF00001,bF00002,c14121A,dF00003|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+141.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c823./141.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c823./173.6a25.a7b21.c.1
		+0b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c791./141.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c823./173.6a25.a7b21.c.10b19.ca10b19.ca2bd
		+6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c791./140.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c824./174.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd
		+2.2b25.cdc2.b27.c790./141.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c823./141.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c8
		+23./140.8a23.a9b22.10b22.b8.b971.
		player_hair_4|32|38|33|16|aF00002,bF00003|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+141.6a25.a6ba23.a8b23.a6b25.a3b28.ab915./141.6a25.a6ba23.a8b23.a6b25.a3b28.ab915./173.6a25.a6ba23.a8b23.a6b25.a3b28.ab883./141.6a25.a6ba23.a8b23.a6b25.a3b28.ab915./173.6a
		+25.a6ba23.a8b23.a6b25.a3b28.ab883./140.6a25.a6ba23.a8b23.a6b25.a3b28.ab916./174.6a25.a6ba23.a8b23.a6b25.a3b28.ab882./141.6a25.a6ba23.a8b23.a6b25.a3b28.ab915./141.6a25.a6b
		+a23.a8b23.a6b25.a3b28.ab915./140.8a23.a8ba22.b8.b1003.
		player_hair_5|32|38|33|16|a14121A,bF00001,cF00002,dF00003,e825F4E|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+45.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.a787./45.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a
		+4cd27.a2cd29.ad31.a787./77.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.a755./45.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd2
		+0.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.a787./77.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.a755./44.5a26.a5b2a23.ab6cba21.
		+ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.e788./78.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.a754./4
		+5.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.a787./45.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4
		+cd27.a2cd29.ad31.a787./45.6a24.2a6b2a21.a2b6c2ba19.ab10cba18.a12ca18.a12ca18.a2c8.2ca18.ac10.ca937.
		player_helm|32|38|33|16|aF000F4,bF000F1,cF000F2,dF000F3|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+109.6a25.a6ba23.ab6cda21.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a850./109.6a25.a6ba23.ab6cda21.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a850./141.6a25.a6b
		+a23.ab6cda21.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a818./109.6a25.a6ba23.ab6cda21.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a850./141.6a25.a6ba23.ab6cda21
		+.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a818./108.6a25.a6ba23.ab6cda21.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a851./142.6a25.a6ba23.ab6cda21.ab8cda20.ab
		+6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a817./109.6a25.a6ba23.ab6cda21.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a850./109.6a25.a6ba23.ab6cda21.ab8cda20.ab6c2da21.a5c2
		+d2a22.a4c2da24.ac2d3a26.3a850./108.8a23.a8ba21.ab8cda20.ab8cda20.a2c6d2ca20.acd6adca21.2a6.2a907.
		player_pants_0|32|38|33|16|a0000F1,b0000F4,c0000F2,d0000F3|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+780.a2b2.3b24.a2cdbdb25.a2cdbdb26.acdbdb26.acdbdb26.2cdbdb26.acdbdb26.acdbdb29.b32.b29.2b111./780.a7b24.2a2cd2b26.a2cdb27.bac2db26.ba2cd27.cbacd27.cbacd27.cbacd28.b31.b32
		+.2b111./812.a2b2.3b24.a2cdb2db25.acdb2db25.acdbcdb25.2cdbcdb25.acdbcdb25.acdb31.b32.b142./780.a6b25.a2cdb2db23.a2cdbc2db23.ac2d2.cd2b21.a2cd3.c2db21.acd5.cdb21.acd5.cdb21
		+.acd5.cdb203./812.a2b2.3b24.2a2cd2b26.a2cd2b27.acd2b27.acd2b27.acd2b30.2b30.b28.3b143./755.b24.a6b25.a2cdbdb25.a2cd2b27.acd2b26.bacdb27.b2cdb27.bacdb27.bacdb31.b32.b27.4b
		+111./812.a7b25.a2cdb27.bac2db26.ba2cd27.cbacd27.cbacd27.cbacd28.b31.b32.2b111./780.a7b24.a2cdbdb25.a2cdbdb26.acdbdb26.acdbdb26.2cdbdb26.acdbdb26.acdbdb29.b32.b29.2b111./7
		+80.a6b25.a2cdbdb25.a2cd2b27.acd2b26.bacdb27.b2cdb27.bacdb27.bacdb31.b32.b27.4b111./780.a6ca23.2a2c2d2c2a22.2acd2.dc2a22.2acd2.dc2a22.2acd2.dc2a22.a2cd2.d2ca22.2acd2.dc2a2
		+2.2acd2.dc2a203.
		player_pants_1|32|38|33|16|a0000F1,b0000F4,c0000F2,d0000F3|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+780.a2b2.3b24.a2cdbdb25.a2cdbdb29.b31.b31.b31.b31.b31.b32.b29.2b111./780.a7b24.2a2cd2b26.a2cdb27.b4.b26.b32.b31.b31.b31.b31.b32.2b111./812.a2b2.3b24.a2cdb2db28.b31.b31.b3
		+1.b31.b31.b32.b142./780.a6b25.a2cdb2db23.a2cdbc2db364./812.a2b2.3b24.2a2cd2b30.b31.b31.b31.b31.b31.b28.3b143./755.b24.a6b25.a2cdbdb25.a2cd2b30.b27.b3.b27.b3.b27.b3.b27.b3
		+.b31.b32.b27.4b111./812.a7b25.a2cdb27.b4.b26.b32.b31.b31.b31.b31.b32.2b111./780.a7b24.a2cdbdb25.a2cdbdb29.b31.b31.b31.b31.b31.b32.b29.2b111./780.a6b25.a2cdbdb25.a2cd2b30.
		+b27.b3.b27.b3.b27.b3.b27.b3.b31.b32.b27.4b111./780.a6ca23.2a2c2d2c2a22.2acd2.dc2a363.
		player_pants_2|32|38|33|16|a0000F1,b0000F4,c0000F2,d0000F3|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+780.a2b2.3b24.a2cdbdb25.a2cdbdb26.acdbdb26.acdbdb26.2cdbdb29.b31.b31.b32.b29.2b111./780.a7b24.2a2cd2b26.a2cdb27.bac2db26.ba2cd27.cbacd28.b31.b31.b31.b32.2b111./812.a2b2.3
		+b24.a2cdb2db25.acdb2db25.acdbcdb25.2cdbcdb28.b31.b31.b32.b142./780.a6b25.a2cdb2db23.a2cdbc2db23.ac2d2.cd2b21.a2cd3.c2db21.acd5.cdb267./812.a2b2.3b24.2a2cd2b26.a2cd2b27.ac
		+d2b27.acd2b30.b31.b31.b28.3b143./755.b24.a6b25.a2cdbdb25.a2cd2b27.acd2b26.bacdb27.b2cdb27.b3.b27.b3.b31.b32.b27.4b111./812.a7b25.a2cdb27.bac2db26.ba2cd27.cbacd28.b31.b31.
		+b31.b32.2b111./780.a7b24.a2cdbdb25.a2cdbdb26.acdbdb26.acdbdb26.2cdbdb29.b31.b31.b32.b29.2b111./780.a6b25.a2cdbdb25.a2cd2b27.acd2b26.bacdb27.b2cdb27.b3.b27.b3.b31.b32.b27.
		+4b111./780.a6ca23.2a2c2d2c2a22.2acd2.dc2a22.2acd2.dc2a22.2acd2.dc2a22.a2cd2.d2ca267.
		player_scarf|32|38|33|16|a14121A,b825F4E,c00F0F2,d00F0F1,e00F0F3,f00F0F4|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+395.ab29.acdb27.ae3c27.a2efe3.f23.aef30.a661./395.ab29.acdb27.ae3c27.a2ef3.ef23.aef30.a661./427.ab29.acdb27.ae3c27.a2efe3.f23.aef30.a629./395.ab29.acdb27.ae3c27.a2efe3.f2
		+3.aef30.a661./427.ab29.acdb27.ae3c27.a2efe3.f23.aef30.a629./394.ab29.a3b27.ab30.b4.3ef28.3f688./428.ab29.acdb27.ae3c4.b22.a2efe3.f23.aef30.f628./395.ab29.acdb27.ae3c27.a2
		+efe27.aef.f28.a661./395.ab29.acdb27.ae3c27.a2ef2e26.aef.f28.a661./427.b8.b56.2fce2f27.fcef29.2f655.
		player_shirt_0|32|38|33|16|a00F001,b00F004,c00F002,d00F003|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+493.a3b.cb24.abacdbcdb23.ab2cdb2db23.cb2cdb2db23.cbc2db2db23.db3.bd2b23.db3.bd2b23.db3.4b23.3b2.3b27.2b431./493.3b2.cb24.bacdb2cdb22.b2c2dbc2db25.db2c2db25.b3c2db25.b3cd2
		+b24.b4cd2b22.2bd4c3b23.8b460./525.a3b.cb24.abacdbcdb23.ab2cdb2db23.cb2cdb2db23.cbc2db2db23.db3.bd2b23.db3.bd2b23.db3.4b23.3b2.3b27.2b399./493.a3b.c25.abacdbcd24.ab2c2dbd2
		+4.2cbcd2.b24.3cb4.b23.d3cb3.b23.d4cb2.b23.2d4c2b24.8b460./525.a3b.cb24.abacdbcdb23.ab2cdb2db23.cb2cdb2db23.cbc2db2db23.db3.bd2b23.db3.bd2b23.db3.4b23.3b2.3b27.2b399./460.
		+b31.ba3.cb24.db5cdb20.c2db5c2db20.2cdb5c2db22.b6c2db23.d5cd2b23.d5cd2b23.2d4c3b24.7b461./525.2a3bcb24.2abacd3b23.acb2cd26.3cb2d26.4c5b23.d5cd2b23.d5cd2b23.2d4c3b23.8b428.
		+/403.2b29.b28.3b27.abacd26.2ab2cd3b23.a2cb2dbdb23.4c2b2db23.6c2db23.d5cd2b23.d5cd2b23.2d4c3b23.8b460./493.2a3bcb24.2abacd6b20.acb2cd6.b19.3cb2d6.b19.4c5b23.d5cdb24.d5cdb2
		+4.2d4c2b24.8b460./491.2a8c20.2a10c2d18.a10cb2d18.acb8cbac18.acb8cbac20.bd6cdb22.b2d4c2db22.b8db23.8d23.10b21.b10.b394.
		player_shirt_1|32|38|33|16|a00F001,b00F004,c00F002,d00F003|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+493.a3b.cb24.abacdbcdb23.ab2cdb2db23.cb2cdb2db23.cbc2db2db23.dbacdbd2b23.dbacdbd2b23.db2cd4b23.3b2.3b27.2b431./493.3b2.cb24.bacdb2cdb22.b2c2dbc2db22.ac2db2c2db22.acdb3c2d
		+b22.2cdb3cd2b24.b4cd2b22.2bd4c3b23.8b460./525.a3b.cb24.abacdbcdb23.ab2cdb2db23.cb2cdb2db23.cbc2db2db23.dbacdbd2b23.dbacdbd2b23.db2cd4b23.3b2.3b27.2b399./493.a3b.c25.abacd
		+bcd24.ab2c2dbd24.2cbcdadb24.3cba2cdb23.d3cbacdb23.d4cb2.b23.2d4c2b24.8b460./525.a3b.cb24.abacdbcdb23.ab2cdb2db23.cb2cdb2db23.cbc2db2db23.dbacdbd2b23.dbacdbd2b23.db2cd4b23
		+.3b2.3b27.2b399./460.b28.acdba3.cb21.ac2db5cdb20.c2db5c2db20.2cdb5c2db22.b6c2db23.d5cd2b23.d5cd2b23.2d4c3b24.7b461./525.2a3bcb24.2abacd3b23.acb2cd2a2c22.3cb2d2c2d22.4c5b2
		+3.d5cd2b23.d5cd2b23.2d4c3b23.8b428./403.2b29.b28.3bacd24.abacdcd24.2ab2cd3b23.a2cb2dbdb23.4c2b2db23.6c2db23.d5cd2b23.d5cd2b23.2d4c3b23.8b460./493.2a3bcb24.2abacd6b20.acb2
		+cd2a2c2.b19.3cb2d2c2d2.b19.4c5b23.d5cdb24.d5cdb24.2d4c2b24.8b460./491.2a8c20.2a10c2d18.a10cb2d18.acb8cbac18.acb8cbac18.acbd6cdbac18.acb2d4c2dbac18.2cb8dbcd21.8d23.10b21.b
		+10.b394.
		player_shirt_2|32|38|33|16|aCCAB8E,b00F004,c00F001,d00F003,e00F002,fB59378|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+498.ab32.b23.c5.2db23.e5.2db23.e5.2db23.d5.d2b23.d5.d2b23.d5.3b23.2b4.2b460./498.ab29.e2.b28.e2db27.2e2db26.3e2db26.3ed2b25.4ed2b24.d4e3b23.8b460./530.ab32.b23.c5.2db23.e
		+5.2db23.e5.2db23.d5.d2b23.d5.d2b23.d5.3b23.2b4.2b428./498.a57.c6.d24.2e30.3e29.d3e28.d4e27.2d4e26.8b460./530.ab32.b23.c5.2db23.e5.2db23.e5.2db23.d5.d2b23.d5.d2b23.d5.3b23
		+.2b4.2b428./493.a3.ab26.c3e2.b24.5e2db24.5e2db23.6e2db23.d5ed2b23.d5ed2b23.2d4e3b24.7b461./526.a3.ab56.ce30.3e29.4e28.d5ed2b23.d5ed2b23.2d4e3b23.8b428./532.b23.c2e4.db23.
		+4e2.2db23.6e2db23.d5ed2b23.d5ed2b23.2d4e3b23.8b460./494.a3.ab56.ce30.3e29.4e28.d5edb24.d5edb24.2d4e2b24.8b460./493.6e.a22.c8e22.c9eb22.b8ebaf20.b8ebaf20.bd6edb22.b2d4e2db
		+22.b8db23.8d23.10b21.b10.b394.
		player_shirt_3|32|38|33|16|a825F4E,b14121A,c00F001,d00F002,e00F003,f00F004|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+363.a30.bca28.bc2da27.b2d2e28.b2e4f.df23.3fcdefdef23.cf2def2ef23.df2def2ef23.dfd2ef2ef23.efcdefe2f23.efcdefe2f23.2f2de4f23.3f2.3f27.2f431./363.a30.bca28.bc2da27.b2d2e28.b
		+2e3f2.df23.2fcdef2def22.f2d2efd2ef22.cd2efd3ef22.cde4f2ef22.2def3de2f24.5fe2f22.10f23.8f460./395.a30.bca28.bc2da27.b2d2e28.b2e4f.df23.3fcdefdef23.cf2def2ef23.df2def2ef23.
		+dfd2ef2ef23.efcdefe2f23.efcdefe2f23.2f2de4f23.3f2.3f27.2f399./363.a30.bca28.bc2da27.b2d2e28.b2e4f.d24.3fcdefde24.cf2d2efe24.2dfdecef24.2d2fc2def23.edfdfcdef23.ed4f2.f23.8
		+f24.8f460./395.a30.bca28.bc2da27.b2d2e28.b2e4f.df23.3fcdefdef23.cf2def2ef23.df2def2ef23.dfd2ef2ef23.efcdefe2f23.efcdefe2f23.2f2de4f23.3f2.3f27.2f399./362.a30.bca28.bc2fa2
		+7.bf2.f28.cde2f3.df21.cd2ef2dc2def20.d2ef3dcd2ef20.2def4d3ef22.f2d4f2ef23.edf3de2f23.ed4fe2f23.9f24.7f461./395.ba29.bcda27.bc2dea26.b2d2ef27.b2e5fdf23.4fcde3f23.cdf2de2c2
		+d22.3df2e2d2e22.2d7f23.edf3de2f23.ed4fe2f23.9f23.8f428./363.a30.bca6.2f20.bc2da4.f22.b2d2e.3fcde21.b2e2fcdede23.4f2de3f23.c2df2efef23.4d2f2ef23.2d4f2ef23.edf3de2f23.ed4fe
		+2f23.9f23.8f460./363.a30.bca28.bc2da27.b2d2e28.b2e5fdf23.4fcde6f20.cdf2de2c2d2.f19.3df2e2d2e2.f19.2d7f23.edf3def24.ed4fef24.8f24.8f460./459.f8.f22.c8fd20.2c2dc4dc2d2e18.c
		+3dc4dcdf2e18.cdf8dfcd18.cdf2d4f2dfcd18.cdfedf2dfdefcd18.cdf2e4f2efcd18.2d10fde21.8f23.10f21.f10.f394.
		polarBear|52|26|23|18|a212633,bEFEBE2,c707984,dE9E5D7,eA1A4A6,fFFFFFF,g1A1316,h1E1519,i3E4349,j8992A6,k3A3A43,lEFEAD9,m834248|idle:0;walk:1,2,3,4;strike:5
		+112.15a34.3a15b3a2.2a25.2a21bac2da23.a23bcd2ed7a15.a4b20dcde2d7b3a12.a2b23dcd12ba10.a2b19de3dc3b4d3e4dba9.ab20de2dc2b7dfg5db2a7.ab21dedcb8d2g6d2ha6.a22dedc17d2ha6.ae23dce
		+9de7da7.ae24dce7d2e6ia9.ae24dc2e5d2e4d2a11.c5dc11dc5dce2c7e4a13.a5dc11ec5d2c2e3c4a17.a4de13c4dec4eca21.a4de7c5ac4dec4eca21.a3d2ec3e2ca5.a3d2ec3e2ca21.a3d2ec3e2ca5.a3d2ec3
		+e2ca21.a4d2ec3e2ca4.a4d2ec3e2ca20.a5dec4eca4.a5dec4eca20.ajkjkjkckjkjka4.ajkjkjkckjkjka21.12a6.12a71./112.15a34.3a15b3a2.2a25.2a21bac2da23.a23bcd2ed7a15.a4b20dcde2d7b3a12
		+.a2b23dcd12ba10.a2b19de3dc3b4d3e4dba9.ab20de2dc2b7dfg5db2a7.ab21dedcb8d2g6d2ha6.a22dedc17d2ha6.ae23dce9de7da7.ae24dce7d2e6ia9.ae24dc2e5d2e4d2a11.aec5dc7dc5dc3e2c7e4a14.ac
		+5dc7ec5dc4ae5c2a19.a4de9c4dec3.a4eca21.a4de3c5ac4dea3.a4eca21.a3d2e2ca5.a3d2ea3.a3e2ca21.a3d2e2ca5.a3d2ea3.a3e2ca21.a4d2e2ca4.a4d2ea2.a4e2ca20.a5de2ca4.a5dea2.a5eca20.ajk
		+jkjkcka4.ajkjkjka2.ajkjkjka21.2a4c2a6.6a4.6a69./60.15a34.3a15b3a2.2a25.2a21bac2da23.a23bcd2ed7a15.a4b20dcde2d7b3a12.a2b23dcd12ba10.a2b19de3dc3b4d3e4dba9.ab20de2dc2b7dfg5d
		+b2a7.ab21dedcb8d2g6d2ha6.a22dedc17d2ha6.ae23dce9de7da7.ae24dce7d2e6ia9.ae24dc2e5d2e4d2a11.a2e15dc5dce2c7e4a13.a5dc11ec5d2c2e3c4a17.a5d13c4dec5ea21.a4de7c5ac4dec4eca21.a4d
		+ec3e2ca5.a3d2ec4eca21.a3d2ec3e2ca5.a3d2ec3e2ca21.a3d2ec4e2ca4.a4d2ec2e2ca21.a4d2ec4eca4.a5dec3e2ca20.a5deckjkjka4.ajkjkjkc4eca20.ajkjkjkc5a6.5acjkjkjka21.6a18.6a71./112.1
		+5a34.3a15b3a2.2a25.2a21bac2da23.a23bcd2ed7a15.a4b20dcde2d7b3a12.a2b23dcd12ba10.a2b19de3dc3b4d3e4dba9.ab20de2dc2b7dfg5db2a7.ab21dedcb8d2g6d2ha6.a22dedc17d2ha6.ae23dce9de7d
		+a7.ae24dce7d2e6ia9.ae24dc2e5d2e4d2a9.a5dc15dc5d2c7e4a11.a5dc15ec5dcec6a15.a4de17c4de2ca21.a4de4a7c5ac4de2ca21.a3d2ea3.a3e2ca5.a3d2e2ca21.a3d2ea3.a3e2ca5.a3d2e2ca21.a4d2ea
		+2.a4e2ca4.a4d2e2ca20.a5dea2.a5eca4.a5de2ca20.ajkjkjka2.ajkjkjka4.ajkjkjkcka21.6a4.6a6.2a4c2a73./60.15a34.3a15b3a2.2a25.2a21bac2da23.a23bcd2ed7a15.a4b20dcde2d7b3a12.a2b23d
		+cd12ba10.a2b19de3dc3b4d3e4dba9.ab20de2dc2b7dfg5db2a7.ab21dedcb8d2g6d2ha6.a22dedc17d2ha6.ae23dce9de7da7.ae24dce7d2e6ia9.ae24dc2e5d2e4d2a11.c5dc16d3e2c7e4a13.a5dc11ec5d2c2e
		+3c4a17.a4de13c5dc4eca21.a4de7c5ac4dec4eca21.a3d2ec4eca5.a4dec3e2ca21.a3d2ec3e2ca5.a3d2ec3e2ca21.a4d2ec2e2ca5.a3d2ec4e2ca20.a5dec3e2ca4.a4d2ec4eca20.ajkjkjkc4eca4.a5deckjk
		+jka21.5acjkjkjka4.ajkjkjkc5a28.6a6.6a77./112.15a34.3a15b3a4.2a23.2a21b2a.a2da21.a25bcd2ed7a13.a4b20d2bcde2d7b3a10.a2b25dcd12ba8.a2b19de5dc3b4d3e4dba7.ab20de4dc2b7dfg5db2a
		+5.ab21de3dcb8d2g6d2ha4.a22de3dc17d2ha4.ae25dce9dedldldl2a5.ae26dce7d2e6ma7.ae19dc5d2ce6d2e6ma7.a5dc14dc5d3ce5d2edldldla7.a5dc14ec4dec2ec2e3d2e5da8.a4de16c4decec3a7e3a9.a4
		+dec2a7c5ac3d2ececa2.7a12.a3d2ea2.a3e2ca5.a3d2e3ca21.a3d2ea2.a4e2ca4.a4d2e2ca21.a4d2ea.a5eca4.a5de3ca20.a5dea.ajkjkjka4.ajkjkjkceca20.ajkjkjka2.6a6.2a4ckjka21.6a18.6a72.
		rex|130|84|79|62|a11140D,bE4DCC9,cDAD1B9,d9D9585,e727B56,f4E5739,gD87967,hECC7A2,i141010,j252C21,k353D2B,lEFEAD9,mD0CAAA,n87816A,o10140C,p2C3225,q242C20,rE3DBC9,s978E7F,t834248,u552930|idle:0;walk:1,2,3,4;windup:5;strike:6
		+2816.a7.a120.aba5.aba4.a114.acba3.abca3.aba114.acba.ab2ca2.abca114.a2cbab3cb2ab2ca115.a2cb5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16e3a109.a2e15f3e2a106.ae20f2ea104.ae
		+23fe2a101.ae13fgh11fia100.ae13f2g12fa100.a28fa99.ajk16f11ka97.2aejk16filililililia96.a2efj2k15fklklklklklka95.ae4fjk25mka94.ae6fjk23nka73.9o13.a8fj23ka67.7op7ep4o7.2ok9f3
		+j20a65.3o6e2p7f2p3e7o2e2k8fmka84.o2pe6f2p7f2p3f4e2pe2f2k7f2mka82.2oe2p7f2p7f2p7f2p3f3k5fmnka81.2o2ef2p6f2p7f3p7f2p4f3k3fmnka80.2o2e3fp7f2p7f2p8f2p5f6k2a75.6o2e4f2p7f2p7f2
		+p7f2p7f5k74.3o4e2p6fp7f2p8f2p7f2p9f2ko72.2o3e4f2p6fp7f2p7f2p8f2p7f2k2mo70.2o2p6f2p6f2p4f6k6f2p7f2p7fk4mo68.2o2e2p5f2p7fp3f2k6e2k4f2p7f2p6fk5mo65.3o2e2fp6f2p6fkf3k2e6f2ek1
		+2f2p4f2k4m2no58.7o3e3fp5f14ke10f2k16f2k3m4no54.4o5e2p5f2p2f17k11f18k4m5no50.4o2p2e4f2p6f17kj3k10f3k5m10k5m3n2o46.5o4fp6f2p5f6k16j2k9f3k19m2n2o47.o2p5f2p4f10k23j2k7f3k19m2
		+nq49.o5f15k9j14o4j2k5f3k19m3nqj2a46.o23j6o14.5o2k3f3k2n17m3nqj2fka46.23o26.3a3k22nqkj2fka100.o21noarkj2fka100.2o18no.arajrfka102.o16no3.a.jrara103.16o7.a.a93.a5fkj2kja118
		+.a5fkj2kja119.a4fkj2kja119.a4fkj2kja119.a3f2kjk2ja120.a3fkj2kja120.a3fkj2kja120.a3fkj2kja120.a3fkj2kja119.a4fkj2kja118.a6fkj2kja116.a8fkj2kja114.a10fkj2kja113.arsrsrsrsrs
		+jsrsa115.4a6j4a456./2816.a7.a120.aba5.aba4.a114.acba3.abca3.aba114.acba.ab2ca2.abca114.a2cbab3cb2ab2ca115.a2cb5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16e3a109.a2e15f3e
		+2a106.ae20f2ea104.ae23fe2a101.ae13fgh11fia100.ae13f2g12fa100.a28fa99.ajk16f11ka97.2aejk16filililililia96.a2efj2k15fklklklklklka95.ae4fjk25mka94.ae6fjk23nka75.7o13.a8fj23k
		+a68.8o6ep4o7.2ok9f3j20a66.3o5e2pe6f2p3e7o2e2k8fmka84.2op2e5f2p7f2p3f4e2pe2f2k7f2mka83.oe2p7f2p7f2p7f2p3f3k5fmnka82.2oef2p6f3p6f3p7f2p4f3k3fmnka81.2o2e2fp7f2p7f2p8f2p5f6k2
		+a80.2o2e3f2p7f2p7f2p7f2p7f5k76.6ope5f2p6f2p8f2p7f2p9f2ko74.2o5e2p6fp7f2p7f2p8f2p7f2k2mo72.2o2e5fp6f2p5f6k5f2p7f2p7fk4mo70.2o2p6f2p6fp4f2k6e2k3f2p7f2p6fk5mo68.2o2e2p5f2p8f
		+4k2e6f2ek11f2p4f2k4m2no66.2o2e2fp6f2p5f6ke10f2k15f2k3m4no60.6o2e3fp4f16k11f17k4m5no56.4o3e2pe4f2p2f18k10f3k4m10k5m3n2o54.3o4e2f2p6f16k5j2k9f3k18m2n2o52.4oe2p5f2p5f6k18j2k
		+7f3k18m2nq50.4o4f2p5f8k25j2k5f3k18m3nqj2a46.o2p5fp3f10k8j20o2k3f3kn17m3nqj2fka45.o4f8k11j6o21.2a4k21nqkj2fka45.o12j11o31.o21noarkj2fka45.12o43.o19no.arajrfka101.2o16no3.a
		+.jrara103.16o7.a.a95.j5fkj121.akj5fka120.a2kj5fka119.a3kj5fka118.a4kj4fka119.a3kj4fka119.a2kj4fka121.akj4fka121.aj4fka123.j4fkj122.a6fkj120.a8fkj118.a10fkj117.arsrsrsrsrs
		+j119.3a7j457./2686.a7.a120.aba5.aba4.a114.acba3.abca3.aba114.acba.ab2ca2.abca114.a2cbab3cb2ab2ca115.a2cb5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16e3a109.a2e15f3e2a106.
		+ae20f2ea104.ae23fe2a101.ae13fgh11fia100.ae13f2g12fa100.a28fa99.ajk16f11ka97.2aejk16filililililia96.a2efj2k15fklklklklklka95.ae4fjk25mka94.ae6fjk23nka73.9o13.a8fj23ka67.7o
		+p7ep4o7.2ok9f3j20a65.3o6e2p7f2p3e7o2e2k8fmka84.o2pe6f2p7f2p3f4e2pe2f2k7f2mka82.2oe2p7f2p7f2p7f2p3f3k5fmnka81.2o2ef2p6f2p7f3p7f2p4f3k3fmnka80.2o2e3fp7f2p7f2p8f2p5f6k2a75.6
		+o2e4f2p7f2p7f2p7f2p7f5k74.3o4e2p6fp7f2p8f2p7f2p9f2ko72.2o3e4f2p6fp7f2p7f2p8f2p7f2k2mo70.2o2p6f2p6f2p4f6k6f2p7f2p7fk4mo68.2o2e2p5f2p7fp3f2k6e2k4f2p7f2p6fk5mo65.3o2e2fp6f2p
		+6fkf3k2e6f2ek12f2p4f2k4m2no58.7o3e3fp5f14ke10f2k16f2k3m4no54.4o5e2p5f2p2f17k11f18k4m5no50.4o2p2e4f2p6f17kj3k10f3k5m10k5m3n2o46.5o4fp6f2p5f6k16j2k9f3k19m2n2o47.o2p5f2p4f10
		+k23j2k7f3k19m2nq49.o5f15k9j14o4j2k5f3k19m3nqj2a46.o23j6o14.5o2k3f3k2n17m3nqj2fka46.23o26.3a3k22nqkj2fka100.o21noarkj2fka100.2o18no.arajrfka102.o16no3.a.jrara103.16o7.a.a2
		+23.a5fkj2kja118.a5fkj2kja119.a4fkj2kja119.a4fkj2kja119.a3f2kjk2ja120.a3fkj2kja120.a3fkj2kja120.a3fkj2kja120.a3fkj2kja119.a4fkj2kja118.a6fkj2kja116.a8fkj2kja114.a10fkj2kja
		+113.arsrsrsrsrsjsrsa115.4a6j4a456./2816.a7.a120.aba5.aba4.a114.acba3.abca3.aba114.acba.ab2ca2.abca114.a2cbab3cb2ab2ca115.a2cb5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16
		+e3a109.a2e15f3e2a106.ae20f2ea104.ae23fe2a101.ae13fgh11fia100.ae13f2g12fa100.a28fa99.ajk16f11ka97.2aejk16filililililia96.a2efj2k15fklklklklklka95.ae4fjk25mka94.ae6fjk23nka
		+71.12o12.a8fj23ka66.6oe2p7e2p3o7.2ok9f3j20a65.2o6ef2p7f2p3e7o2e2k8fmka83.2o2p7f2p7f2p3f4e2pe2f2k7f2mka81.2o2e2p6f3p7f2p7f2p3f3k5fmnka80.2o2e2f2p6f2p7f2p8f2p4f3k3fmnka75.6
		+o2e4fp7f2p7f2p8f2p5f6k2a73.3o3e2pe5f2p7f2p7f2p7f2p7f5k72.3o3e3f2p6fp7f2p8f2p7f2p9f2ko70.2o2pe5f2p6f2p7f2p7f2p8f2p7f2k2mo68.2o2e2p5f2p7f2p3f6k7f2p7f2p7fk4mo65.3o2e2fp6f2p9
		+f3k6e2k5f2p7f2p6fk5mo55.10o3e3fp6f5k3f5k2e6f2ek13f2p4f2k4m2no51.4op7e2p5f2p3f15ke10f3k16f2k3m4no45.6o3fp7f2p6f20k11f19k4m5no44.o2p5f2p7f2p4f9k7j3k3jk10f3k7m8k6m3n2o45.o6f
		+17k21j2k9f3k20m2n2o47.o12j8k11j7o7j2k7f3k20m2nq50.12o10j9o7.8o2k5f3kn19m3nqj2a59.10o25.2k3f3k4n16m3nqj2fka94.5ak23nqkj2fka100.2o20noarkj2fka101.o18no.arajrfka102.2o14n2o3
		+.a.jrara104.14o8.a.a91.a5fk2a5kja113.a5fka2.a5kja112.a4fka4.a5kja111.a4fka5.a5kja110.a4fka6.a4kja111.a3fka6.a4kja111.a4fka4.a4kja113.a3fka4.a4kja113.a4fka2.a4kja115.a4fka
		+.a4kja115.a5fkj6kja114.a6fkj6kja113.a7fkj6kja112.arsrsrsrjsrsrsrsa114.5a2j8a453./2686.a7.a120.aba5.aba4.a114.acba3.abca3.aba114.acba.ab2ca2.abca114.a2cbab3cb2ab2ca115.a2c
		+b5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16e3a109.a2e15f3e2a106.ae20f2ea104.ae23fe2a101.ae13fgh11fia100.ae13f2g12fa100.a28fa99.ajk16f11ka97.2aejk16filililililia96.a2ef
		+j2k15fklklklklklka95.ae4fjk25mka94.ae6fjk23nka73.9o13.a8fj23ka67.7op7ep4o7.2ok9f3j20a65.3o6e2p7f2p3e7o2e2k8fmka84.o2pe6f2p7f2p3f4e2pe2f2k7f2mka82.2oe2p7f2p7f2p7f2p3f3k5fm
		+nka81.2o2ef2p6f2p7f3p7f2p4f3k3fmnka80.2o2e3fp7f2p7f2p8f2p5f6k2a75.6o2e4f2p7f2p7f2p7f2p7f5k74.3o4e2p6fp7f2p8f2p7f2p9f2ko72.2o3e4f2p6fp7f2p7f2p8f2p7f2k2mo70.2o2p6f2p6f2p4f6
		+k6f2p7f2p7fk4mo68.2o2e2p5f2p7fp3f2k6e2k4f2p7f2p6fk5mo65.3o2e2fp6f2p6fkf3k2e6f2ek12f2p4f2k4m2no58.7o3e3fp5f14ke10f2k16f2k3m4no54.4o5e2p5f2p2f17k11f18k4m5no50.4o2p2e4f2p6f1
		+7kj3k10f3k5m10k5m3n2o46.5o4fp6f2p5f6k16j2k9f3k19m2n2o47.o2p5f2p4f10k23j2k7f3k19m2nq49.o5f15k9j14o4j2k5f3k19m3nqj2a46.o23j6o14.5o2k3f3k2n17m3nqj2fka46.23o26.3a3k22nqkj2fka
		+100.o21noarkj2fka100.2o18no.arajrfka102.o16no3.a.jrara103.16o7.a.a223.a5fkj2kja118.a5fkj2kja119.a4fkj2kja119.a4fkj2kja119.a3f2kjk2ja120.a3fkj2kja120.a3fkj2kja120.a3fkj2kj
		+a120.a3fkj2kja119.a4fkj2kja118.a6fkj2kja116.a8fkj2kja114.a10fkj2kja113.arsrsrsrsrsjsrsa115.4a6j4a456./2423.a7.a120.aba5.aba4.a114.acba3.abca3.aba114.acba.ab2ca2.abca114.a
		+2cbab3cb2ab2ca115.a2cb5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16e3a109.a2e15f3e2a106.ae20f2ea104.ae23fe2a101.ae13fgh11fia100.ae13f2g12fa100.a28fa100.ak16f11ka100.jk16f
		+lililililila98.2ajk14f12ta98.a2ej2k12f2t10ua98.ae3fjk11f2t9u2a98.ae5fjk9f2t10u2a98.a7fjk9m13ta97.a8fjk8nlililililililia77.8o11.ak8fjk21na69.8o7ep4o7.2k7f2mj20ka68.2o6e2p7
		+f2p3e7o3k5fmnk21a67.2ope6f2p7f2p3f4e2pef3k3fmnka86.2oe2p7f2p7f2p7f2p3f8k86.o2ef2p6f3p6f3p7f2p4f5kfo84.2oe3fp7f2p7f2p8f2p10fo79.5o2e3f2p7f2p7f2p7f2p11fo76.3o2e2pe5f2p6f2p8
		+f2p7f2p9f2ko73.3o3e2f2p6fp7f2p7f2p8f2p7f2k2mo71.2op2e4f2p6f2p4f6k6f2p7f2p7fk4mo69.2oe2p5f2p7fp3f2k6e2k4f2p7f2p6fk5mo67.2o2efp6f2p8f3k2e6f2ek12f2p4f2k4m2no64.3o2e2f2p6f5k2
		+f5ke10f2k16f2k3m4no57.7op2e4fp4f15k11f18k4m5no54.3o6ep6fpf19k10f3k5m10k5m3n2o51.4o2pe5f2p5f9k6j2k4j2k9f3k19m2n2o48.5o4fp6f2p3f6k19j2k7f3k19m2nq49.o2p5f2p3f10k11j6o8j2k5f3
		+k19m3nqj2a46.o5f14k8j6o6.9o2k3f3k2n17m3nqj2fka45.o21j6o22.3a3k22nqkj2fka46.21o33.o21noarkj2fka100.o19no.arajrfka101.2o16no3.a.jrara103.16o7.a.a93.a5fk2ja120.a5fkja122.j4f
		+kj123.j4fkj123.j3f2kj124.j3fkj124.j3fkja123.a3fkja123.a3fk2ja121.a4fkjkja119.a6fkjkja117.a8fkjkja115.a10fkjkja114.arsrsrsrsrsjsra116.6a4j3a457./3341.a7.a120.aba5.aba4.a11
		+4.acba3.abca3.aba114.acba.ab2ca2.abca114.a2cbab3cb2ab2ca115.a2cb5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16e3a109.a2e15f3e2a106.ae20f2ea104.ae23fe2a101.ae13fgh11fia96.4
		+aje13f2g12fa94.2a4ej28fa93.a2e4fjk16f11ka92.ke6fjk16flililililila66.10o14.oke7fjk14f12ta60.7o2p7ep4o7.3oek8fj2k12f2t10ua59.2o7e2p7f2p3e7o3efk9fjk11f2t9u2a58.2o2p7f2p7f2p3
		+f4e2pe4f2k8fmjk9f2t10u2a56.2o2e2p7f2p7f2p7f2p5f2k7f2mkjk9m13ta54.o2e2f2p6f2p7f3p7f2p5f3k5fmnka.ak8nlililililililia50.3oe4fp7f2p7f2p8f2p6f3k3fmnka3.ak21na44.6op2e4f2p7f2p7
		+f2p7f2p8f6k2a5.a20ka42.3o5e2p6fp7f2p8f2p7f2p9f3k2a8.20a41.2op2e5fp6f2p7f2p7f2p8f2p7f2k2mo69.2oe2p6f2p6f2p5f6k5f2p7f2p7fk4mo66.3o2efp6f2p11f3k6e2k3f2p7f2p6fk5mo59.7o3e2f2p
		+6f2p5f7k2e6f2ek11f2p4f2k4m2no54.5o4e2pe5fp4f16ke10f2k15f2k3m4no49.5o2p3e3f2p6fp21k11f17k4m5no45.4o5fp6f2p6f17k4j2k10f3k4m10k5m3n2o45.o2p5f2p5f12k20j2k9f3k18m2n2o47.o4f17k
		+26j2k7f3k18m2nq49.o26j19o3j2k5f3k18m3nqj2a47.26o19.4o2k3f3k2n16m3nqj2fka96.3a3k21nqkj2fka100.o21noarkj2fka100.2o18no.arajrfka102.2o15no3.a.jrara94.j5fkj2.15o7.a.a94.akj5f
		+ka120.a2kj5fka119.a3kj5fka118.a4kj4fka119.a3kj4fka119.a2kj4fka121.akj4fka121.aj4fka123.j4fkj122.a6fkj120.a8fkj118.a10fkj117.arsrsrsrsrsj119.3a7j457.
		scorpion|32|19|16|13|a291B15,bC2A16E,cB28B5A,d7F613D,e381F1C,f5F4536,g816244,hD87067|idle:0;walk:1,2,3,4;strike:5
		+69.4a27.a4ba25.abcd2cba23.ab2c2a2cba22.acda2.acda22.a2ca3.acea20.abca4.a2ea9.3a8.acd5a3f10ab2ca7.a2cf2bd2bd2bd3bfb4c2aca7.afb2cd2cd2cd4c2fg5ca8.a3cd2cd2cd2ch3cfa3ga9.ag14
		+cga.3a11.a14ga17.a12fa19.af2af2af2afa21.a2.a2.a2.a47./69.4a27.a4ba25.abcd2cba23.ab2c2a2cba22.acda2.acda22.a2ca3.acea20.abca4.a2ea9.3a8.acd5a3f10ab2ca7.a2cf2bd2bd2bd3bfb4c
		+2aca7.afb2cd2cd2cd4c2fg5ca8.a3cd2cd2cd2ch3cfa3ga9.ag14cga.3a11.a14ga17.2a12f20.af2af2af2afa21.a2.a2.a2.a46./37.4a27.a4ba25.abcd2cba23.ab2c2a2cba22.acda2.acda22.a2ca3.acea
		+20.abca4.a2ea9.3a8.acd5a3f10ab2ca7.a2cf2bd2bd2bd3bfb4c2aca7.afb2cd2cd2cd4c2fg5ca8.a3cd2cd2cd2ch3cfa3ga9.ag14cga.3a11.a14ga17.a12fa19.ac2ac2ac2aca20.af2af2af2afa21.a2.a2.a
		+2.a47./69.4a27.a4ba25.abcd2cba23.ab2c2a2cba22.acda2.acda22.a2ca3.acea20.abca4.a2ea9.3a8.acd5a3f10ab2ca7.a2cf2bd2bd2bd3bfb4c2aca7.afb2cd2cd2cd4c2fg5ca8.a3cd2cd2cd2ch3cfa3g
		+a9.ag14cga.3a11.a14ga17.a3fa5fa3f19.afa.afafa.afa20.a3.a.a3.a46./37.4a27.a4ba25.abcd2cba23.ab2c2a2cba22.acda2.acda22.a2ca3.acea20.abca4.a2ea9.3a8.acd5a3f10ab2ca7.a2cf2bd2
		+bd2bd3bfb4c2aca7.afb2cd2cd2cd4c2fg5ca8.a3cd2cd2cd2ch3cfa3ga9.ag14cga.3a11.a14ga17.a12fa19.ac2ac2ac2aca20.af2af2af2afa21.a2.a2.a2.a47./69.8a23.a8b2a20.abcd2cd2cdcb2a17.ab2
		+c7a2cdb2a15.acda7.2a2c2ea14.a2ca9.2a2ea13.abca12.2a3.3a8.acd18ab2ca7.a2cf2bd2bd2bd3bfb4c2aca7.afb2cd2cd2cd4c2fg5ca8.a3cd2cd2cd2ch3cfa3ga9.ag14cga.3a11.a14ga17.a12fa19.af2
		+af2af2afa21.a2.a2.a2.a47.
		sentinel|50|42|36|22|a1A1F2F,bA6C3DD,c8EB2D1,d647A96,eF2FAFD,f566882,g86D4DF,hC4F1F4,iFFFFFF,j49556F,kA8E2EE|idle:0;fly:0,1;charge:2;strike:3
		+21.a48.aba46.abcda46.ada48.a32.a48.aba46.abcda14.2a30.ada14.a2ba30.a14.aeb2ca43.aeb3cfa41.aeb4cdfa39.aeb6cdfa37.aeb8cdfa30.a4.aeb10cdfa28.aba3.aeb11cda4.a22.aecda2.a2b5c2
		+g4cda3.aba20.aeb2cda.ab5cg2hg3cda2.aecda19.ab3cda.ab4cgh2ihg2cda.aeb2cda18.ab3cda.ab4cgh2ihg2cda.ab3cda18.ab3cda.ab5cg2hg3cda.ab3cda19.abcda2.ab6c2g4cda.ab3cda20.ada3.ad1
		+2cja2.abcda22.a4.a2d10c2ja3.ada29.a2d8c2ja5.a31.a2d6c2ja39.a2d4c2ja41.a2d2c2ja43.a2d2ja32.a12.adja32.aba12.2a32.abcda46.ada48.a442./421.2a47.a2ba45.aeb2ca12.a30.aeb3cfa10
		+.aba28.aeb4cdfa8.abcda26.aeb6cdfa8.ada26.aeb8cdfa8.a26.aeb10cdfa4.a24.a4.aeb11cda3.aba22.aba3.a2b5c2g4cda2.aecda20.aecda2.ab5cg2hg3cda.aeb2cda18.aeb2cda.ab4cgh2ihg2cda.ab
		+3cda18.ab3cda.ab4cgh2ihg2cda.ab3cda18.ab3cda.ab5cg2hg3cda.ab3cda18.ab3cda.ab6c2g4cda2.abcda20.abcda2.ad12cja3.ada22.ada3.a2d10c2ja4.a24.a5.a2d8c2ja37.a2d6c2ja39.a2d4c2ja4
		+1.a2d2c2ja9.a33.a2d2ja9.aba33.adja9.abcda33.2a11.ada48.a464./271.2a47.a2ba45.aeb2ca35.a7.aeb3cfa8.a24.aba5.aeb4cdfa6.aba22.abcda3.aeb2c2g2cdfa4.abcda22.ada3.aeb2cg2hg2cdf
		+a4.ada24.a3.aeb2cgh2ihg2cdfa4.a29.aebcgh4ihg2cda33.2a2bcg6ig2cd2a31.abjbcgh6ihgcdjba29.aecjbcg8igcjecda27.aebcjbcg8igjeb2cda26.ab2cjbcgh6ihgjb3cda26.ab2cjb2cg6igcjb3cda26
		+.ab2cjd2cgh4ihgcjb3cda27.abcj2d2cgh2ihg2c2jbcda29.ad2a2d2cg2hg2c2j2ada31.a2.a2d2c2g2c2ja2.a36.a2d4c2ja41.a2d2c2ja35.a7.a2d2ja8.a26.aba7.adja8.aba24.abcda7.2a8.abcda24.ada
		+19.ada26.a21.a566./372.2a47.a2ba45.aeb2ca43.aeb3cfa41.aeb4cdfa39.aeb6cdfa37.aeb8cdfa4.2a29.aeb10cdfa2.a2b3a26.aeb11cda.aeb3cd2a24.a2b5c2g4cd2aeb6cda3.k19.ab5cg2hg3cda.ad4
		+cd2a2.k.i.k17.ab4cgh2ihg2cda2.2a2d2a5.3i18.ab4cgh2ihg2cda4.2a5.k5ik16.ab5cg2hg3cda5.2a6.3i18.ab6c2g4cda4.a2b3a2.k.i.k17.ad12cja3.aeb3cd2a2.k19.a2d10c2ja2.aeb6cda22.a2d8c2
		+ja4.ad4cd2a24.a2d6c2ja6.2a2d2a27.a2d4c2ja9.2a30.a2d2c2ja43.a2d2ja45.adja47.2a576.
		sheep|30|22|19|12|a1E1B24,bF6F2EA,c3A3541,d6B6675,e524C59,fDCD6D3,gFFFFFF,h16141A,i2A2530,jB9B1BB|idle:0;walk:1,2,3,4;alt:5
		+64.2a.3a.3a.2a2.2a11.2a2ba3ba3ba2ba3c2a8.a15b2c2d2e3a4.a2bf14bcd6ea3.a9bf7bc3egh3ea2.a17bc8ea2.abf12bf3bc5ecia2.a19bc4ecia2.aj4bf13bj5ca3.a2j16b2j5a5.a3j12b3ja11.a3ja4ja4
		+ja2ja13.acdec3j.2acdecjca13.adececa3.adececa13.adececa3.adececa13.adececa3.adececa13.a2e3ca3.a2e3ca13.a2ic2ia3.a2ic2ia14.2a.2a5.2a.2a40./64.2a.3a.3a.2a2.2a11.2a2ba3ba3ba2
		+ba3c2a8.a15b2c2d2e3a4.a2bf14bcd6ea3.a9bf7bc3egh3ea2.a17bc8ea2.abf12bf3bc5ecia2.a19bc4ecia2.aj4bf13bj5ca3.a2j16b2j5a5.a3j12b3ja11.a3ja4ja4ja2ja13.2ajcdeca.cdec.3aeca12.acd
		+ea2.adea3.aeca12.acdea2.adea3.aeca12.acdea2.adea3.aeca12.ac2ea2.a2ea3.a2ca12.ac2ia2.a2ia3.a2ia13.aca4.2a5.2a38./34.2a.3a.3a.2a2.2a11.2a2ba3ba3ba2ba3c2a8.a15b2c2d2e3a4.a2b
		+f14bcd6ea3.a9bf7bc3egh3ea2.a17bc8ea2.abf12bf3bc5ecia2.a19bc4ecia2.aj4bf13bj5ca3.a2j16b2j5a5.a3j12b3ja11.a3ja4ja4ja2ja13.3a.4j.2acdeca15.adececa3.adececa13.adececa3.adecec
		+a13.adececa3.adececa13.ade3ca3.a2ececa13.a2ec2ia3.a2i3ca13.a2i3a5.3a2ia14.2a11.2a40./64.2a.3a.3a.2a2.2a11.2a2ba3ba3ba2ba3c2a8.a15b2c2d2e3a4.a2bf14bcd6ea3.a9bf7bc3egh3ea2.
		+a17bc8ea2.abf12bf3bc5ecia2.a19bc4ecia2.aj4bf13bj5ca3.a2j16b2j5a5.a3j12b3ja11.a3ja4ja4ja2ja12.adec.2a2jcj2ajcdea12.adea3.aeca2.acdea12.adea3.aeca2.acdea12.adea3.aeca2.acde
		+a12.a2ea3.a2ca2.ac2ea12.a2ia3.a2ia2.ac2ia13.2a5.2a4.aca41./34.2a.3a.3a.2a2.2a11.2a2ba3ba3ba2ba3c2a8.a15b2c2d2e3a4.a2bf14bcd6ea3.a9bf7bc3egh3ea2.a17bc8ea2.abf12bf3bc5ecia2
		+.a19bc4ecia2.aj4bf13bj5ca3.a2j16b2j5a5.a3j12b3ja11.a3ja4ja4ja2ja13.acdec3a.4a.2jca13.adececa3.adececa13.adececa3.adececa13.adececa3.adececa13.a2ececa3.ade3ca13.a2i3ca3.a2
		+ec2ia14.3a2ia3.a2i3a18.2a5.2a43./64.2a.3a.3a.2a15.2a2ba3ba3ba2b2a12.a17ba10.a2bf16ba9.a9bf10ba8.a20ba8.abf12bf5ba8.a20bca7.aj4bf13b3c2a5.a2j16b2c2d2e3a3.a3j12b3jcd6ea3.a3
		+ja4ja4ja2j2a3egh3ea3.acdec3j.2acdecj2c8ea4.adececa3.adecec2a5ecia4.adececa3.adececa.a4ecia4.adececa3.adececa2.a4ca5.a2e3ca3.a2e3ca3.4a6.a2ic2ia3.a2ic2ia14.2a.2a5.2a.2a40.
		sheep_1|30|22|19|12|a1E1B24,b3A3541,c6B6675,d524C59,eEFD6C8,fFFFFFF,g16141A,hE2C3B5,i2A2530,jC4A197,kA28079|idle:0;walk:1,2,3,4;alt:5
		+79.2a27.a2b2a12.13ab2c2d3a7.2a12eabc6da5.a15eb3dfg3da3.a2e14hb8da3.a17hb5dbia3.a18hb4dbia3.aj15h2j2a4ba4.a2j12h3ja2.4a6.a15ja14.2a11k2a16.acdb3k3abcdbdba13.acdbdba3.acdbd
		+ba13.acdbdba3.acdbdba13.acdbdba3.acdbdba13.a2d3ba3.a2d3ba13.a2ib2ia3.a2ib2ia14.2a.2a5.2a.2a40./79.2a27.a2b2a12.13ab2c2d3a7.2a12eabc6da5.a15eb3dfg3da3.a2e14hb8da3.a17hb5db
		+ia3.a18hb4dbia3.aj15h2j2a4ba4.a2j12h3ja2.4a6.a15ja14.2a11k2a17.kbcdb2abcdb3.adba12.abcda2.acda3.adba12.abcda2.acda3.adba12.abcda2.acda3.adba12.ab2da2.a2da3.a2ba12.ab2ia2.
		+a2ia3.a2ia13.aba4.2a5.2a38./49.2a27.a2b2a12.13ab2c2d3a7.2a12eabc6da5.a15eb3dfg3da3.a2e14hb8da3.a17hb5dbia3.a18hb4dbia3.aj15h2j2a4ba4.a2j12h3ja2.4a6.a15ja14.2a11k2a17.2a4k
		+3abcda16.acdbdba3.acdbdba13.acdbdba3.acdbdba13.acdbdba3.acdbdba13.acd3ba3.a2dbdba13.a2db2ia3.a2i3ba13.a2i3a5.3a2ia14.2a11.2a40./79.2a27.a2b2a12.13ab2c2d3a7.2a12eabc6da5.a
		+15eb3dfg3da3.a2e14hb8da3.a17hb5dbia3.a18hb4dbia3.aj15h2j2a4ba4.a2j12h3ja2.4a6.a15ja14.2a11k2a14.acdb3a4k2akbcda12.acda3.adba2.abcda12.acda3.adba2.abcda12.acda3.adba2.abcd
		+a12.a2da3.a2ba2.ab2da12.a2ia3.a2ia2.ab2ia13.2a5.2a4.aba41./49.2a27.a2b2a12.13ab2c2d3a7.2a12eabc6da5.a15eb3dfg3da3.a2e14hb8da3.a17hb5dbia3.a18hb4dbia3.aj15h2j2a4ba4.a2j12h
		+3ja2.4a6.a15ja14.2a11k2a16.acdb8a.adba13.acdbdba3.acdbdba13.acdbdba3.acdbdba13.acdbdba3.acdbdba13.a2dbdba3.acd3ba13.a2i3ba3.a2db2ia14.3a2ia3.a2i3a18.2a5.2a43./125.12a16.2
		+a12e2a13.a16ea11.a2e15ha11.a18ha10.a18h3a8.aj15h2j3b2a6.a2j12h3j2b2c2d3a4.a15ja.ac6da4.2a11k2a2.a3dfg3da4.acdb3k3abcdbd2b8da4.acdbdba3.acdbdb2a5dbia4.acdbdba3.acdbdba.a4d
		+bia4.acdbdba3.acdbdba2.a4ba5.a2d3ba3.a2d3ba3.4a6.a2ib2ia3.a2ib2ia14.2a.2a5.2a.2a40.
		skeleton|42|42|36|18|a17151C,bDBE1E9,cA8B0BD,d7B8391,e555C6A,fF7F3E5,gE3DBC7,hF3F6FA,i2A2732,jB2B9C7,k92DDE8,lB9B09C,mFDFDF2,n887D73,o977A49,pCCB36B,qA98960,r644933,s806044,t846547,uE6EBF5,vA6B1C3,w644A34|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:6
		+226.5a35.2a5b2a32.a2b7ca30.a2b8cda29.ad9ed2a29.af9gaha28.af3g3i3gahja27.a3g3iki2gahja27.a4g3igigahja27.al9gahja28.al2gmimimlahja28.a8i2ahja29.algmimimlahja29.an6l2ahja25.
		+2a.a2f6n.ahja24.adcnfginfgn2gao2pa24.acq2afgngln2g2arsa24.act2agingl4narsa24.act2afgnf5gapa25.act2ag2in6la26.adt2af3g4n2a28.ada.aigl2in32.a.af5ga34.a6n35.aglnlna35.aglnln
		+a35.af2gn2la34.aglnlna35.aglnlna35.aglnlna35.abcdndea33.ab3cdndea33.3a2n3a188./226.5a35.2a5b2a32.a2b7ca30.a2b8cda29.ad9eda.a28.af9g2aha27.af3g3i3g2ahja26.a3g3iki2g2ahja26
		+.a4g3igig2ahja26.al9g2ahja27.al2gmimiml2ahja27.a8ia.ahja28.algmimiml2ahja28.an6la.ahja24.2a.a2f6n2.ahja23.adcnfg2infgng2ao2pa23.acq2af2gnglnga.arsa23.act2ag2ingl3n2arsa23
		+.act2af2gnf5gapa24.act2ag3in6la25.adt2af4g3n3a27.ada.aigl2ia32.a.af5ga34.a6n36.aglna37.agl2n37.anf2ga36.angla36.al2ngla35.al2ngla35.acnb2cda34.acnb2cda35.2a2n2a189./268.5
		+a35.2a5b2a32.a2b7ca30.a2b8cda29.ad9ed2a29.af9gaha28.af3g3i3gahja27.a3g3iki2gahja27.a4g3igigahja27.al9gahja28.al2gmimimlahja28.a8i2ahja29.algmimimlahja29.an6l2ahja25.2a.a2
		+f6n.ahja24.adcnfginfgn2gao2pa24.acq2afgngln2g2arsa24.act2agingl4narsa24.act2afgnf5gapa25.act2ag2in6la26.adt2af3g4n2a28.ada.aigl2in32.a.nf5ga34.a6na34.agla.alna33.af2g2ag2
		+la32.agla.alna33.agla.alna33.agl2acdea33.abcdnc2dea31.ab3cdn3a33.5a191./226.5a35.2a5b2a32.a2b7ca30.a2b8cda29.ad9eda30.af8gaha29.af3g3i2gahja28.a3g3ikigahja28.a4g3igiahja2
		+8.al8gahja29.al2gmimimahja29.a8iahja30.algmimimahja30.an6lahja26.2a.a2f6nahja25.adcnfgnfgnigao2pa25.acq2afngln3garsa25.act2agngl4narsa25.act2afnf5gapa26.act2agin6la27.adt
		+2af2g5na29.ada.aigl2ina31.a.af5gn34.a6n34.agla.alna33.agla.aln2a31.af2ga2.ag2la30.agla3.alna30.agla5.alna29.agla5.alna29.abcda3.ac2dea28.ab2cda2.ac2dea29.4a4.4a186./268.5
		+a35.2a5b2a32.a2b7ca30.a2b8cda29.ad9ed2a29.af9gaha28.af3g3i3gahja27.a3g3iki2gahja27.a4g3igigahja27.al9gahja28.al2gmimimlahja28.a8i2ahja29.algmimimlahja29.an6l2ahja25.2a.a2
		+f6n.ahja24.adcnfginfgn2gao2pa24.acq2afgngln2g2arsa24.act2agingl4narsa24.act2afgnf5gapa25.act2ag2in6la26.adt2af3g4n2a28.ada.aigl2in32.a.nf5ga35.6n37.aglna37.af2gna36.aglna
		+37.aglna36.abcdna36.ab2cdna36.4ndea36.5a188./52.2a39.apsa37.aropa36.ahproa35.ahjo4a.5a27.ahj2a.afgn5b2a24.ahja3.aglfn6ca22.ahja4.anglfn5cda21.aja5.adnglfn4eda22.a7.afngln
		+5ga30.afg2n3i3ga30.a3g3iki2ga30.a4g3igiga30.al9ga31.al2gmimimla31.a8ia33.algmimimla32.an6la29.2a.a2f6n29.adcnfg5i2ga28.acq2af7ga28.act2ag6ila28.act2af7ga28.act2ag6ila28.a
		+dt2af6ga30.ada.aigl2in32.a.af5ga35.6na35.agl2na36.agl2na36.af2gna36.aglna37.ngln38.ngln38.nbcdn36.ab3cdn36.a4n191./270.5a35.2a5b2a32.a2b7ca30.a2b8cda29.ad9eda30.af9ga30.a
		+f3g3i3ga30.a3g3iki2ga30.a4g3igiga.3u26.al9ga3.2u26.al2gmimimla4.vu25.a8ia6.vu25.algmimimla6.v24.2an6la28.2a.a2fg5na28.adcnfg2i6n11a17.acq2afgnf2gfg2ao9ja16.act2agin4lap2r
		+p9ha15.act2af2g5n2ao10a16.act2ag6ila.a26.adt2af6ga30.ada.aigl2in32.2anf5ga34.a4n2a35.agl2n37.anf2ga36.angla36.al2ngla35.al2ngla35.acnb2cda34.acnb2cda35.2a2n2a189./226.5a3
		+5.na5b2a32.n2b7ca30.a2b8cda29.ad9eda30.nf9ga30.nf3g3i3ga30.n3g3iki2ga30.n4g3igiga30.nl9ga30.anl2gmimimla30.an7i5a27.aopnlgmimad3cda27.ar2n3lad2q3tda26.an2f3nacq4tda26.nfg
		+2i2nac2tbcwea27.nfgnfgac2tcdwea27.aginglac3t2wea27.af2g2nadt4wda27.ag5iad3wda28.af6ga3da30.aigl2in.3a30.af5ga34.a6n35.aglnlna35.aglnlna35.af2gn2la34.aglnlna35.aglnlna35.a
		+glnlna35.abcdndea33.ab3cdndea33.3a2n3a188.
		slime|26|20|17|13|a1C362E,b97CC84,cFFFFFF,d7ABD6B,e548751,f15231C,g3B6241,h213724|idle:0;hop:1;strike:2
		+113.8a16.2a8b2a13.a3b2c5b2d2a10.a2b3c2b8da8.a2b2cb11dea6.a3b14dea6.ab3dfc6dfc3d2ea4.ab4d2f6d2f3d2ea4.ab17d2ea4.a17d2ega4.a7d6h4d2ega4.ae16d2ega5.a3e12d2ega7.ag14ega9.16a3
		+1./10.6a18.2a6b2a15.a3b2c3b2da13.a2b3cb6da12.ab2cb7dea11.a3b9dea11.ab2dfc4dfc2dea10.ab2d2f4d2f2dea10.ab12dea10.a12d2ea10.a5d4h3d2ea10.a12d2ea10.ae11dega11.ae9d2ega11.a2e8
		+dega13.a10ea15.a8ga17.8a61./140.8a16.2a8b3a11.2a3b2c5b3d2a8.a3b3cb10d2a5.a3b2cb6dfc5dea3.a3b7dfcd2f5dea3.ab9d2f7d2ea2.ab11d7hd2ea2.ab10dhchchc2hdega2.a11d8hdega2.ae11dhch
		+chc2dega3.a2e16d2ega4.ag17ega6.19a28.
		tiger|46|24|20|20|a1E1510,bCB925D,cD5A46E,d291D1A,e6D4937,fDBC86E,g15111A,hF5EEDF,iD4838F,j956847,k392121,lD3C8B9,mFFFFFF,n8C464E|idle:0;walk:1,2,3,4;strike:5
		+75.2a5.2a9.2a25.a2ba3.a2ba7.acba23.ab2db3ab2dba6.aba24.a4b3c4bca5.ada8.16a.acbd3bd4bca4.a2b2a4.2a16cec8bf3ba5.abdb4a2c2bd3bd3bd3bdbebd7bg2bha6.2abdbec4bd3bd3bd3bdbe7b5hia
		+8.2aec5bd3bd3bd3bdbejd4b6ha11.a21bej4b2h3kha11.a3bd4bd4bd4bd3be3j6ha12.aj2bd4bd4bd4bd4b2e5j2a14.e3be12he3b3e6a16.abdbe12lebdbedja21.a2bj5e8ae2bjejea21.abdjejdea8.abdjedea
		+21.a2bje2jea8.a2bjejea21.a2bje2jea8.a2bjejea21.a3he3la8.a3he2la21.a2hle3la8.a2hle2la22.3a.3a10.6a107./75.2a5.2a9.2a25.a2ba3.a2ba7.acba23.ab2db3ab2dba6.aba24.a4b3c4bca5.ad
		+a8.16a.acbd3bd4bca4.a2b2a4.2a16cec8bf3ba5.abdb4a2c2bd3bd3bd3bdbebd7bg2bha6.2abdbec4bd3bd3bd3bdbe7b5hia8.2aec5bd3bd3bd3bdbejd4b6ha11.a21bej4b2h3kha11.a3bd4bd4bd4bd3be3j6ha
		+12.aj2bd4bd4bd4bd4b2e5j2a14.aje3be8he3be2j2ej2e3a17.aebdbe8lebdbe3ajdja21.e2bje8ae2bje2.a2jea21.ebdje8.abdja2.ajdea21.e2bje8.a2bja2.a2jea21.e2bje8.a2bja2.a2jea21.e3he8.a3
		+ha2.a3la21.e2hle8.a2hla2.a3la22.3e10.3a4.3a105./29.2a5.2a9.2a25.a2ba3.a2ba7.acba23.ab2db3ab2dba6.aba24.a4b3c4bca5.ada8.16a.acbd3bd4bca4.a2b2a4.2a16cec8bf3ba5.abdb4a2c2bd3
		+bd3bd3bdbebd7bg2bha6.2abdbec4bd3bd3bd3bdbe7b5hia8.2aec5bd3bd3bd3bdbejd4b6ha11.a21bej4b2h3kha11.a3bd4bd4bd4bd3be3j6ha12.aj2bd4bd4bd4bd4b2e5j2a14.a2j14he3be2a.5a16.a3be12le
		+bdbe2ja21.abdb5e8ae2bjedja21.a2bjejdea8.abdjejea21.abdje2jea8.a2bjedea21.a2bje2jea8.a2bjejea21.a2bje3la8.a3hejea21.a3he3la8.a2hle2la21.a2hl4a10.2ae3la22.3a17.3a107./75.2a
		+5.2a9.2a25.a2ba3.a2ba7.acba23.ab2db3ab2dba6.aba24.a4b3c4bca5.ada8.16a.acbd3bd4bca4.a2b2a4.2a16cec8bf3ba5.abdb4a2c2bd3bd3bd3bdbebd7bg2bha6.2abdbec4bd3bd3bd3bdbe7b5hia8.2ae
		+c5bd3bd3bd3bdbejd4b6ha11.a21bej4b2h3kha11.a3bd4bd4bd4bd3be3j6ha12.aj2bd4bd4bd4bd4b2e5j2a12.a3be16he3be.5a14.abdbej15lebdba20.a2bj4a5e7a2e2bja20.abdja3.ajdea7.aebdja20.a2b
		+ja3.a2jea7.ae2bja20.a2bja3.a2jea7.ae2bja20.a3ha3.a3la7.ae3ha20.a2hla3.a3la7.ae2hla21.3a5.3a9.a2ea108./29.2a5.2a9.2a25.a2ba3.a2ba7.acba23.ab2db3ab2dba6.aba24.a4b3c4bca5.ad
		+a8.16a.acbd3bd4bca4.a2b2a4.2a16cec8bf3ba5.abdb4a2c2bd3bd3bd3bdbebd7bg2bha6.2abdbec4bd3bd3bd3bdbe7b5hia8.2aec5bd3bd3bd3bdbejd4b6ha11.a21bej4b2h3kha11.a3bd4bd4bd4bd3be3j6ha
		+12.aj2bd4bd4bd4bd4b2e5j2a14.e3be15h2j2e6a16.abdbe12le3bedja21.a2bj5e8aebdbejea21.abdje2jea8.a2bjedea21.a2bjejdea8.abdjejea21.a2bje2jea8.a2bjejea21.a3he2jea8.a2bje2la21.a2
		+hle3la8.a3he2la22.4a3la8.a2hle2a27.3a10.3a110./77.2a5.2a7.2a27.a2ba3.a2ba5.acba25.ab2db3ab2dba4.aba26.a4b3c4bca3.ada8.16a3.acbd3bd4bca2.a2b2a4.2a16c3ac8bf3bha2.abdb4a2c2b
		+d3bd3bd3bdb2cebd7bg2bhia3.2abdbec4bd3bd3bd3bd3be7bhmhmhma6.2aec5bd3bd3bd3bd3bejd4bh5na9.a23bej4bh5na9.a3bd4bd4bd4bd5be3jbhmhmhma9.aj2bd4bd4bd4bd4bj3a3j4ha10.a3be15he3be3.
		+7a11.abdbe15lebdbe21.a2bje2a5e8ae2bje21.abdja2.ajdea8.ebdje21.a2bja2.a2jea8.e2bje21.a2bja2.a2jea8.e2bje21.a3ha2.a3la8.e3he21.a2hla2.a3la8.e2hle22.3a4.3a10.3e108.
		warden|84|94|90|42|a120E18,b6A6F7E,c989EAD,dD6DAE3,eF3F5F9,f100C18,g57473A,h392E25,i625773,j3B3148,k292233,l0C0912,mCEA8EE,nFCEEFC,o2B2D38,p818493,q5A5E6C,r3E404D,sD9C4F4,tA481CE,u1C1825,v1B1525,wC096E9,xEFE0FA|idle:0;fly:0,1;windup:2;strike:3;cast:4
		+723.12a71.a2b2c7de5a67.a2b2c8d4e2a66.2a2b5a2c4d3ea64.fgh2a5.5a2d2ea64.fghf11.2ad2ea63.fghf13.a2ea63.fghf14.aea63.fghf15.a64.fghf80.fghf66.2a12.fghf65.a2ia11.fghf64.ai2jia
		+10.fghf63.ai4jia9.fghf62.ai6jia8.fghf61.ai8jka7.fghf60.ai6j4lka6.fghf59.ai6j6lka5.fghf59.ai5j7lka5.fghf58.ai5j5lmnlka5.fghf58.ai5j8lka5.fghf58.ai5j4lm3lka5.fghf58.ak6j6l2
		+ka5.fghf58.ak7j4l2ka6.fghf59.a2kjk2j6oa7.fghf60.ak2a2o5pq2a6.fghf61.2ao4p5qra5.fghf60.2ao2p7q3ra4.fghf59.apo2p7q2roa5.fghf58.a2po8q3r2o5.fghf58.ap2qo7r4oa5.3of57.ap4q10or
		+a4.a2qro57.a9qs4q2ra3.ap2q2ra56.ar8qt4q2ra3.a3qroa56.a2r11q2roa4.aqr2o58.a2r10q2roa4.a2qro59.a11r2oa4.ap3qoa57.2a13o6a2qr2oa56.a3i2j2k5jk5jku2ar3o56.a3i3jk5j2k5jkua.3of56
		+.a3i3j2k5jk6jkuafghf56.a3i3j2k5jk6jkuafghf55.a3i3j2k5j2k6jkuafghf55.a3i3j2k6j2k6jk2ughf55.a3i3j2k6j2k6jk2ughf54.a3i4j2k5j2k7jk2ughf54.a3i4j2k5j2k7jk2ughf54.a3i4j2k6j2k7jk
		+2uhf54.a3i4j2k6j2k7jk2uhf53.a4i3j2k7j2k7jk2uhf53.a4i3j2k7j2k7jk2uhf53.a4i4j2k6j2k8jk2uf53.a4i4j2k6j2k8jk2uf52.a4i4j2k7j2k8jk2uf52.a4i4j2k7j2k8jk2uf52.a4i4j2k7j3k8jk2u52.a
		+4i4j2k7j3k8jk2u52.a4i4j2k7j3k8jk2u51.a4i4j3k7j2k9jk2u51.a4i4j3k7j2k9jk2u51.a4i5j2k7j3k9jkua50.a4i5j2k7j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.
		+a4i5j3k8j2k10jkua48.a4i5j3k8j2k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i5j2k9j3k10jkua46.a5i5j2k9j3k10jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3
		+k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua43.a2ia2i2ja2j2ka4ja4ja3kja4ja4jaua43.a2iaia2jaja2kaja2jaja2jakakjaja2jaja2jaua43.a
		+i2aiaj2ajaj2akaj2ajaj2akak2ajaj2ajaj2aka43.aia.2aja.2aja.2aja.2aja.2aka.2aja.2aja.a45.a4.a4.a4.a4.a4.a4.a4.a197./807.12a71.a2b2c7de5a67.a2b2c8d4e2a66.2a2b5a2c4d3ea64.fgh2
		+a5.5a2d2ea64.fghf11.2ad2ea63.fghf13.a2ea63.fghf14.aea63.fghf15.a64.fghf80.fghf66.2a12.fghf65.a2ia11.fghf64.ai2jia10.fghf63.ai4jia9.fghf62.ai6jia8.fghf61.ai8jka7.fghf60.ai
		+6j4lka6.fghf59.ai6j6lka5.fghf59.ai5j7lka5.fghf58.ai5j5lmnlka5.fghf58.ai5j8lka5.fghf58.ai5j4lm3lka5.fghf58.ak6j6l2ka5.fghf58.ak7j4l2ka6.fghf59.a2kjk2j6oa7.fghf60.ak2a2o5pq
		+2a6.fghf61.2ao4p5qra5.fghf60.2ao2p7q3ra4.fghf59.apo2p7q2roa5.fghf58.a2po8q3r2o5.fghf58.ap2qo7r4oa5.3of57.ap4q10ora4.a2qro57.a9qs4q2ra3.ap2q2ra56.ar8qt4q2ra3.a3qroa56.a2r1
		+1q2roa4.aqr2o58.a2r10q2roa4.a2qro59.a11r2oa4.ap3qoa57.2a13o6a2qr2oa56.a3i2j2k5jk5jku2ar3o56.a3i3jk5j2k5jkua.3of56.a3i3j2k5jk6jkuafghf56.a3i3j2k5jk6jkuafghf55.a3i3j2k5j2k6
		+jkuafghf55.a3i3j2k6j2k6jk2ughf55.a3i3j2k6j2k6jk2ughf54.a3i4j2k5j2k7jk2ughf54.a3i4j2k5j2k7jk2ughf54.a3i4j2k6j2k7jk2uhf54.a3i4j2k6j2k7jk2uhf53.a4i3j2k7j2k7jk2uhf53.a4i3j2k7
		+j2k7jk2uhf53.a4i4j2k6j2k8jk2uf53.a4i4j2k6j2k8jk2uf52.a4i4j2k7j2k8jk2uf52.a4i4j2k7j2k8jk2uf52.a4i4j2k7j3k8jk2u52.a4i4j2k7j3k8jk2u52.a4i4j2k7j3k8jk2u51.a4i4j3k7j2k9jk2u51.a
		+4i4j3k7j2k9jk2u51.a4i5j2k7j3k9jkua51.a4i5j2k7j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j3k8j2k10jkua48.a4i5j3k8j2k10jkua47.a5i4j3k8j3k10jkua
		+47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i5j2k9j3k10jkua47.a5i5j2k9j3k10jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k9j3k11jkua44.a5i5j3k
		+9j3k11jkua44.a5i5j3k9j3k11jkua44.a4ia4ja2k2ja4ja2j2ka4ja4jajkua44.aia2iaja2jaka2jaja2jaja2kaja2jaja2jajaua44.aiai2ajaj2akak2ajaj2ajak2ajaj2ajaj2ajaka45.2aia.2aja.2aka.2aj
		+a.2aka.2aja.2aja.2aka47.a4.a4.a4.a4.a4.a4.a4.a108./695.3a79.2a2eda76.2a2e2dca75.a2e2dc2ahf73.ae2dc2afghf72.ae2dca3.fghf70.ae2d2a4.fghf69.ae2da7.fghf68.aeda9.fghf66.aeda10
		+.fghf66.aea12.fghf66.a13.fghf5.2a74.fghf3.a2ia74.fghf.ai2jia73.fghfai4jia73.fgui6jia72.fui8jka71.ai6j4lka69.ai6j6lka68.ai5j7lka67.ai5j5lmnlka67.ai5j8lka67.ai5j4lm3lka67.a
		+k6j6l2ka67.ak7j4l2ka69.a2kjk2j6oa71.ak2a2o5pq2a71.2ao4p5qra69.2ao2p7q3ra67.apo2p7q2r2oa66.a2po8qr2o2pqa65.ap2qo7ro2p2qra64.ap4q7op2q2ra65.a9qsop2qr2o66.ar8qop2q2r2o66.a2r
		+7qo2q5of66.a2r7q4or2of67.a9r5oghf65.2a13oa4u63.a3i2j2k5jk5jkua61.a3i3jk5j2k5jk2u61.a3i3j2k5jk6jkua60.a3i3j2k5jk6jk2u59.a3i3j2k5j2k6jkua59.a3i3j2k6j2k6jkua58.a3i3j2k6j2k6j
		+kua57.a3i4j2k5j2k7jkua57.a3i4j2k5j2k7jkua57.a3i4j2k6j2k7jkua56.a3i4j2k6j2k7jkua55.a4i3j2k7j2k7jkua55.a4i3j2k7j2k7jkua55.a4i4j2k6j2k8jkua54.a4i4j2k6j2k8jkua53.a4i4j2k7j2k8
		+jkua53.a4i4j2k7j2k8jkua53.a4i4j2k7j3k8jkua52.a4i4j2k7j3k8jkua52.a4i4j2k7j3k8jkua51.a4i4j3k7j2k9jkua51.a4i4j3k7j2k9jkua51.a4i5j2k7j3k9jkua49.a4i5j2k7j3k9jkua49.a4i5j2k8j3k
		+9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j3k8j2k10jkua48.a4i5j3k8j2k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i5j2k9j3k10jkua46.a5i5
		+j2k9j3k10jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua43.a3iai3jaj3ka4ja4ja2k2ja4ja3jka45.a
		+2iaia2jaja2kaja2jaja2jaka2jaja2jajajk2a44.ai2aiaj2ajak2ajaj2ajaj2akaj2ajaj2ajaj2aua43.aia.2aja.2aka.2aja.2aja.2aja.2aja.2aja.a45.a4.a4.a4.a4.a4.a4.a4.a197./1717.2a81.a2ia
		+79.ai2jia77.ai4jia75.ai6jia73.ai8jka71.ai6j4lka69.ai6j6lka68.ai5j7lka67.ai5j5lmnlka67.ai5j8lka67.ai5j4lm3lka67.ak6j6l2ka67.ak7j4l2ka69.a2kjkj2v5oa71.ak2avghv3pq2a71.2aopv
		+ghv4qra69.2ao2pqvghv2q3ra67.apo2p3qvgh2vroa67.a2po6qv6o67.ap2qo5ro2p2q2o4a62.ap4q5op9qra61.a9qo2q4r5qoa60.ar8qt6or2oq2oa60.a2r9q2o2r6oa62.a2r10q2roafg2of63.a11r2oa2.f2ghf
		+61.2a13o4avfghf59.a3i2j2k5jk5jkuafghf57.a3i3jk5j2k5jkua.fghf56.a3i3j2k5jk6jkua.fghf55.a3i3j2k5jk6jkua2.fghf3.2w48.a3i3j2k5j2k6jkua3.fghf4.2w46.a3i3j2k6j2k6jkua3.fgh2f4.3w
		+43.a3i3j2k6j2k6jkua4.f2ghf6.4w38.a3i4j2k5j2k7jkua5.2fghf9.4w34.a3i4j2k5j2k7jkua7.fghf46.a3i4j2k6j2k7jkua7.fghf45.a3i4j2k6j2k7jkua8.fghf43.a4i3j2k7j2k7jkua9.fghf42.a4i3j2k
		+7j2k7jkua10.fgh2f40.a4i4j2k6j2k8jkua10.f2gha39.a4i4j2k6j2k8jkua11.2faea37.a4i4j2k7j2k8jkua13.a2e2a35.a4i4j2k7j2k8jkua14.a2ed3a32.a4i4j2k7j3k8jkua14.a2e3d8a24.a4i4j2k7j3k8
		+jkua15.2a6d3c2ba23.a4i4j2k7j3k8jkua17.3a2d3c3ba22.a4i4j3k7j2k9jkua20.4a2b2a23.a4i4j3k7j2k9jkua24.2a25.a4i5j2k7j3k9jkua51.a4i5j2k7j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k
		+9jkua49.a4i5j2k8j3k9jkua49.a4i5j3k8j2k10jkua48.a4i5j3k8j2k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i5j2k9j3k10jkua47.a5i5j2k9j3k10jkua45.a5i
		+5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua44.a4ia4ja2k2ja4ja2j2ka4ja4jajkua44.aia2iaja2jaka2jaja2j
		+aja2kaja2jaja2jajaua44.aiai2ajaj2akak2ajaj2ajak2ajaj2ajaj2ajaka45.2aia.2aja.2aka.2aja.2aka.2aja.2aja.2aka47.a4.a4.a4.a4.a4.a4.a4.a108./615.12a71.a2b2c7de5a67.a2b2c8d4e2a6
		+6.2a2b5a2c4d3ea64.fgh2a5.5a2d2ea64.fghf11.2ad2ea63.fghf13.a2ea63.fghf14.aea63.fghf15.a64.fghf80.fghf80.fghf6.2a72.fghf5.a2ia71.fghf4.ai2jia70.fghf3.ai4jia69.fghf2.ai6jia6
		+8.fghf.ai8jka67.fghfai6j4lka66.fghui6j6lka65.fghui5j7lka65.fgui5j5lmnlka65.fgui5j8lka65.fgui5j4lm3lka65.fguk6j6l2ka65.fguk7j4l2ka66.fghu2kjk2j6oa67.fghfak2a2o5pq2a66.fghf
		+.2ao4p5qra65.fghf2ao2p7q3ra8.w.w53.fghopo2p7q2roa8.w3xw52.fgo2po7q3or2o7.w2xn2xw51.fgop2qo5ro2pq3o3a5.w3xw52.fop4q5op3qr5q3a3.w.w53.fo9qo2q4r5qpqa58.for8qt7o2ro2qoa58.fo2
		+r9q2o2ro3ar2oa59.fgo2r10q2roa2.3a60.fgho11r2oa66.fg2u13o5a62.fu3i2j2k5jk5jkua61.u3i3jk5j2k5jkua61.u3i3j2k5jk6jkua60.u3i3j2k5jk6jkua59.a3i3j2k5j2k6jkua59.a3i3j2k6j2k6jkua5
		+8.a3i3j2k6j2k6jkua57.a3i4j2k5j2k7jkua57.a3i4j2k5j2k7jkua57.a3i4j2k6j2k7jkua56.a3i4j2k6j2k7jkua55.a4i3j2k7j2k7jkua55.a4i3j2k7j2k7jkua55.a4i4j2k6j2k8jkua54.a4i4j2k6j2k8jkua
		+53.a4i4j2k7j2k8jkua53.a4i4j2k7j2k8jkua53.a4i4j2k7j3k8jkua52.a4i4j2k7j3k8jkua52.a4i4j2k7j3k8jkua51.a4i4j3k7j2k9jkua51.a4i4j3k7j2k9jkua51.a4i5j2k7j3k9jkua50.a4i5j2k7j3k9jku
		+a49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j3k8j2k10jkua48.a4i5j3k8j2k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i5j2k9j
		+3k10jkua46.a5i5j2k9j3k10jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua43.a2ia2i2ja2j2ka4ja4j
		+a3kja4ja4jaua43.a2iaia2jaja2kaja2jaja2jakakjaja2jaja2jaua43.ai2aiaj2ajaj2akaj2ajaj2akak2ajaj2ajaj2aka43.aia.2aja.2aja.2aja.2aja.2aka.2aja.2aja.a45.a4.a4.a4.a4.a4.a4.a4.a2
		+81.
		wolf|34|21|18|14.5|a17171E,b898D9A,cABABAE,d5E606D,e41424F,fD8BE67,g15111A,hCBCED6,i1A1418,j888993,kFFFFFF,l8C464E|idle:0;walk:1,2,3,4;strike:5
		+21.a3.a10.2a16.aba.aba8.a2ca14.abdbabdba6.ac2bca13.a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10be9b3ha5.aec12bebd5b4hia6.e14bed3b6ha7.a15be4d2j3a8.ad15b3e3a12
		+.a2d11h2d2a16.a2be8je2beda16.abd4e5aebd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.a5ea5.a4ea17.2a.2a7.4a46./21.a3.a10.2a16.aba.aba8.a2c
		+a14.abdbabdba6.ac2bca13.a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10be9b3ha5.aec12bebd5b4hia6.e14bed3b6ha7.a15be4d2j3a8.ad15b3e3a12.a2d11h2d2a17.2e2be4je2be3a
		+2da15.aebde4aebde2.adea15.aebda4.abda2.adea15.aebda4.abda2.adea15.aebda4.abda2.adea15.aebda4.abda2.adea15.a3ea4.a2ea2.a2ea16.aea6.2a4.2a44./2.2a16.aba.aba8.a2ca14.abdbabd
		+ba6.ac2bca13.a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10be9b3ha5.aec12bebd5b4hia6.e14bed3b6ha7.a15be4d2j3a8.ad15b3e3a12.a2d11h2d2a17.2ad8je2be18.a2b4e5aebded
		+a16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abd3ea5.a4ea16.a2e3a7.a3ea17.2a12.2a46./21.a3.a10.2a16.aba.aba8.a2ca14.abdbabdba6.ac2bca13.a3b
		+c3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10be9b3ha5.aec12bebd5b4hia6.e14bed3b6ha7.a15be4d2j3a8.ad15b3e3a12.a2d11h2d2a14.a2bead9jde2ba14.abda.2a4e3a3ebda14.abda3
		+.adea3.adebda14.abda3.adea3.adebda14.abda3.adea3.adebda14.abda3.adea3.adebda14.a2ea3.a2ea3.a4ea15.2a5.2a5.4a46./2.2a16.aba.aba8.a2ca14.abdbabdba6.ac2bca13.a3bc3bca5.ac4ba
		+.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10be9b3ha5.aec12bebd5b4hia6.e14bed3b6ha7.a15be4d2j3a8.ad15b3e3a12.a2d11h2d2a16.a2be9jd2eda16.abd4e5ae2b2ea16.abdedea5.abd2ea16.abde
		+dea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.a3edea5.abd2ea17.3a2ea5.a3ea21.2a7.2a48./23.a3.a8.2a18.aba.aba6.a2ca16.abdbabdba4.ac2bca15.a3bc3bca3.ac4ba.12a.a2c6bc2a2
		+.ad3b2e12cec5bfg3bha2.adbe2c12be9b3hi3.aec14bebd5bkhkhka4.e16bed4b5la5.a17be2d2bkhkhka5.ad16bdea2d3hja7.a2d11h2d2a2.6a7.a2bed9jde2ba15.abd3a4e4a2ebda15.abda2.adea4.aebda1
		+5.abda2.adea4.aebda15.abda2.adea4.aebda15.abda2.adea4.aebda15.a2ea2.a2ea4.a3ea16.2a4.2a6.aea46.
		wolf_1|34|21|18|14.5|a231A14,bB8976E,cC9AD88,d836950,e5F4A3B,f291D18,g15111A,hB85B5B,iE5D4B5,j864343,k1A1418,l9F8F7E,mFFFFFF,n8C464E|idle:0;walk:1,2,3,4;strike:5
		+21.a3.a10.2a16.aba.aba8.a2ca14.abdbabdba6.ac2bca13.a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10beh8b3ia5.aec12behj5b4ika6.e14bed3b6ia7.a15be4d2l3a8.ad15b3e3a1
		+2.a2d11i2d2a16.a2be8le2beda16.abd4e5aebd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.a5ea5.a4ea17.2a.2a7.4a46./21.a3.a10.2a16.aba.aba8.a2
		+ca14.abdbabdba6.ac2bca13.a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10beh8b3ia5.aec12behj5b4ika6.e14bed3b6ia7.a15be4d2l3a8.ad15b3e3a12.a2d11i2d2a17.2e2be4le2be
		+3a2da15.aebde4aebde2.adea15.aebda4.abda2.adea15.aebda4.abda2.adea15.aebda4.abda2.adea15.aebda4.abda2.adea15.a3ea4.a2ea2.a2ea16.aea6.2a4.2a44./2.2a16.aba.aba8.a2ca14.abdba
		+bdba6.ac2bca13.a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10beh8b3ia5.aec12behj5b4ika6.e14bed3b6ia7.a15be4d2l3a8.ad15b3e3a12.a2d11i2d2a17.2ad8le2be18.a2b4e5aeb
		+deda16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abd3ea5.a4ea16.a2e3a7.a3ea17.2a12.2a46./21.a3.a10.2a16.aba.aba8.a2ca14.abdbabdba6.ac2bca13.
		+a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10beh8b3ia5.aec12behj5b4ika6.e14bed3b6ia7.a15be4d2l3a8.ad15b3e3a12.a2d11i2d2a14.a2bead9lde2ba14.abda.2a4e3a3ebda14.a
		+bda3.adea3.adebda14.abda3.adea3.adebda14.abda3.adea3.adebda14.abda3.adea3.adebda14.a2ea3.a2ea3.a4ea15.2a5.2a5.4a46./2.2a16.aba.aba8.a2ca14.abdbabdba6.ac2bca13.a3bc3bca5.a
		+c4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10beh8b3ia5.aec12behj5b4ika6.e14bed3b6ia7.a15be4d2l3a8.ad15b3e3a12.a2d11i2d2a16.a2be9ld2eda16.abd4e5ae2b2ea16.abdedea5.abd2ea16
		+.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.a3edea5.abd2ea17.3a2ea5.a3ea21.2a7.2a48./23.a3.a8.2a18.aba.aba6.a2ca16.abdbabdba4.ac2bca15.a3bc3bca3.ac4ba.12a.a2c6
		+bc2a2.ad3b2e12cec5bfg3bia2.adbe2c12beh8b3ik3.aec14behj5bmimima4.e16bed4b5na5.a17be2d2bmimima5.ad16bdea2d3ila7.a2d11i2d2a2.6a7.a2bed9lde2ba15.abd3a4e4a2ebda15.abda2.adea4.
		+aebda15.abda2.adea4.aebda15.abda2.adea4.aebda15.abda2.adea4.aebda15.a2ea2.a2ea4.a3ea16.2a4.2a6.aea46.
		wraith|28|28|24|13|a150F1E,b826AA1,c5F4981,d100C16,eEFE9AF,fD9C769,g42325C,h2F2443,i9893AF,jD5D1E4|idle:0;fly:0,1;strike:2
		+37.6a20.2a6b2a17.a2b7cba15.ab11ca14.ab2c6d3ca13.ab3c5ded3ca12.ab3cdf3dfd3ca12.ab4c5d4cga12.a5c3d5c2ga11.a13cga11.ab13c2ga10.ab13cga11.a14cga11.a14c2ga10.a14cga11.ag13c2ga
		+10.ag13c2ga11.ag12c2ga11.ag11c2ga12.ag2ca5ca2c2ga13.agc2a3c2ac2ga14.aga.agcga.aga16.a2.ag2a3.a21.a100./65.6a20.2a6b2a17.a2b7cba15.ab11ca14.ab2c6d3ca13.ab3c5ded3ca12.ab3cd
		+f3dfd3ca12.ab4c5d4cga12.a5c3d5c2ga11.a13cga11.ab13c2ga10.ab13cga11.a14cga11.a14c2ga10.a14cga11.ag13c2ga10.ag13c2ga11.ag12c2ga11.ag12c2ga12.ag2ca5cac2ga13.agca.a3c2acga15.
		+aga.agca2.aga16.a3.aga3.a22.a70./38.6a20.2a6b2a17.a2b7cba15.ab11ca14.ab2c6d3ca13.ab3c5ded3ca12.ab3cdf3dfd3ca12.ab4c5d4cga12.a5c3d5c2gh11.a7c4h2cghia9.ab6chb3c5hia8.ab6ch6
		+c2jhia8.a7chg4c2jijh9.a8ch3g2hjhja9.a9c3h2ch2a10.ag13c2ga10.ag13c2ga11.ag12c2ga11.ag11c2ga12.ag2ca5ca2c2ga13.agc2a3c2ac2ga14.aga.agcga.aga16.a2.ag2a3.a21.a99.
		zombie|34|34|31|13.5|a17191E,b37462E,c242E1E,d9AB978,e7FA964,f3E5A3E,g5A794D,h1A1418,iD87067,j381E26,kE7E2C9,l6FA098,m4A8382,n365C60,o294248,p6C719B,q494F7D,r343858,s262940,t494048,u3A3238,v2A242C,w1E1A20|idle:0;walk:1,2,3,4;windup:5;strike:6
		+14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4
		+m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.ap2qrs2rsa24.ap2qrs2rsa25.a2qrs2rsa25.a2qrs2rsa25.aq2rsr2sa
		+25.aeg2agfa26.aeg2agfa25.a4ts3ua24.a4tvs2uwa24.4as4a50./14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2
		+gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.a2p
		+2qrsrsa25.ap2qr2sa27.a2q2rsa27.sp2qrs28.as2qra28.asega29.aseg2a28.as4ta27.as3tva28.a3sa52./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega
		+23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa2
		+5.a3on3oa25.spoq2orosa24.a6srsa24.ap2qrsqrsa25.a2qrsq2rsa24.a2qr2a2rsa24.aq2r2agfsa24.aega.agfa25.aeg2a3ua24.a4ts3uwa23.a4tvs3a25.5a54./14.5a28.a5b2a25.a8ba23.ac3b5da23.a
		+c2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m
		+4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.ap2qrsq2rsa22.ap2qr2aq2rsa22.a2q2ra.a2r2sa20.ap2qra2.aq2rsa20.a2qra4.a2rsa20.aega5.agfa21.aeg
		+a5.agf2a20.a3ta4.a4ua19.a3tva3.a3uwa20.4a5.4a48./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.
		+a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.spoq2orosa24.a6srsa24.a2pqrs2r
		+sa25.ap2qrsrsa26.a2qrsrsa26.aegr3sa26.aegsgfa26.a3tsgfa26.a3tvs2ua26.2a2s3uwa28.5a50./13.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fef.a21.acg2e2hih2e2fa20.a2g7e2f2
		+a21.ag2ejkj2fdeaga20.f2gej2fd2e2ga20.2o4flm2eg2a20.a2l2f2lmnfga21.a2lf2l2mnf2a21.a2lmfm2nofa23.al3m4fna23.a7m2na23.an5m2na24.a2n4m2na25.a2n3mnoa25.anomnmoa26.3on4o26.aoq2
		+oroa26.a6srsa24.ap2qrs2rsa24.ap2qrsrsa26.a2qr3sa26.a2qr2sa27.aq2rsa28.aegsa29.aegsa28.a4tsa27.a4tvsa27.2a3sa53./50.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.a
		+cg2e2hih2ea22.a2g7ega23.ag2ekjkjka24.a2ge5ja22.2af2ge5ja21.a3l2fgkjk2ga20.a2l3m6fa20.a2l3m7f21.al3mf2lm2f2ea.a18.a4mf3mne3fafa17.an3mf3no2e2d3f17.a2n3m3f2g3edfga17.a2n3mn
		+ofa2g2e2ga16.aonomnmoa2.2agaga16.ap3on3oa4.a.a17.spqoq2osoa24.a6srsa25.ap2qr2sa27.a2q2rsa27.sp2qrs28.as2qra28.asega29.aseg2a28.as4ta27.as3tva28.a3sa52.
		zombie_1|34|34|31|13.5|a17191E,b837451,c574D36,dC8B98B,eBCA97D,f5A5848,g81785D,h1A1418,iD6AA63,j381E26,kE7E2C9,lB1A17D,m9D8761,n6C5E49,o4B4238,p918778,q75694F,r504839,s37312C,t494048,u3A3238,v2A242C,w1E1A20|idle:0;walk:1,2,3,4;windup:5;strike:6
		+14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4
		+m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.ap2qrs2rsa24.ap2qrs2rsa25.a2qrs2rsa25.a2qrs2rsa25.aq2rsr2sa
		+25.aeg2agfa26.aeg2agfa25.a4ts3ua24.a4tvs2uwa24.4as4a50./14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2
		+gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.a2p
		+2qrsrsa25.ap2qr2sa27.a2q2rsa27.sp2qrs28.as2qra28.asega29.aseg2a28.as4ta27.as3tva28.a3sa52./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega
		+23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa2
		+5.a3on3oa25.spoq2orosa24.a6srsa24.ap2qrsqrsa25.a2qrsq2rsa24.a2qr2a2rsa24.aq2r2agfsa24.aega.agfa25.aeg2a3ua24.a4ts3uwa23.a4tvs3a25.5a54./14.5a28.a5b2a25.a8ba23.ac3b5da23.a
		+c2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m
		+4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.ap2qrsq2rsa22.ap2qr2aq2rsa22.a2q2ra.a2r2sa20.ap2qra2.aq2rsa20.a2qra4.a2rsa20.aega5.agfa21.aeg
		+a5.agf2a20.a3ta4.a4ua19.a3tva3.a3uwa20.4a5.4a48./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.
		+a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.spoq2orosa24.a6srsa24.a2pqrs2r
		+sa25.ap2qrsrsa26.a2qrsrsa26.aegr3sa26.aegsgfa26.a3tsgfa26.a3tvs2ua26.2a2s3uwa28.5a50./13.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fef.a21.acg2e2hih2e2fa20.a2g7e2f2
		+a21.ag2ejkj2fdeaga20.f2gej2fd2e2ga20.2o4flm2eg2a20.a2l2f2lmnfga21.a2lf2l2mnf2a21.a2lmfm2nofa23.al3m4fna23.a7m2na23.an5m2na24.a2n4m2na25.a2n3mnoa25.anomnmoa26.3on4o26.aoq2
		+oroa26.a6srsa24.ap2qrs2rsa24.ap2qrsrsa26.a2qr3sa26.a2qr2sa27.aq2rsa28.aegsa29.aegsa28.a4tsa27.a4tvsa27.2a3sa53./50.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.a
		+cg2e2hih2ea22.a2g7ega23.ag2ekjkjka24.a2ge5ja22.2af2ge5ja21.a3l2fgkjk2ga20.a2l3m6fa20.a2l3m7f21.al3mf2lm2f2ea.a18.a4mf3mne3fafa17.an3mf3no2e2d3f17.a2n3m3f2g3edfga17.a2n3mn
		+ofa2g2e2ga16.aonomnmoa2.2agaga16.ap3on3oa4.a.a17.spqoq2osoa24.a6srsa25.ap2qr2sa27.a2q2rsa27.sp2qrs28.as2qra28.asega29.aseg2a28.as4ta27.as3tva28.a3sa52.
		zombie_2|34|34|31|13.5|a17191E,b324955,c213038,d93B6A4,e71A09D,f3A5357,g507272,h1A1418,i78D6DF,j381E26,kE7E2C9,l789179,m506D59,n394C44,o283636,p677186,q3F4C5F,r2C3544,s212633,t494048,u3A3238,v2A242C,w1E1A20|idle:0;walk:1,2,3,4;windup:5;strike:6
		+14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4
		+m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.ap2qrs2rsa24.ap2qrs2rsa25.a2qrs2rsa25.a2qrs2rsa25.aq2rsr2sa
		+25.aeg2agfa26.aeg2agfa25.a4ts3ua24.a4tvs2uwa24.4as4a50./14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2
		+gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.a2p
		+2qrsrsa25.ap2qr2sa27.a2q2rsa27.sp2qrs28.as2qra28.asega29.aseg2a28.as4ta27.as3tva28.a3sa52./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega
		+23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa2
		+5.a3on3oa25.spoq2orosa24.a6srsa24.ap2qrsqrsa25.a2qrsq2rsa24.a2qr2a2rsa24.aq2r2agfsa24.aega.agfa25.aeg2a3ua24.a4ts3uwa23.a4tvs3a25.5a54./14.5a28.a5b2a25.a8ba23.ac3b5da23.a
		+c2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m
		+4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.ap2qrsq2rsa22.ap2qr2aq2rsa22.a2q2ra.a2r2sa20.ap2qra2.aq2rsa20.a2qra4.a2rsa20.aega5.agfa21.aeg
		+a5.agf2a20.a3ta4.a4ua19.a3tva3.a3uwa20.4a5.4a48./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.
		+a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.spoq2orosa24.a6srsa24.a2pqrs2r
		+sa25.ap2qrsrsa26.a2qrsrsa26.aegr3sa26.aegsgfa26.a3tsgfa26.a3tvs2ua26.2a2s3uwa28.5a50./13.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fef.a21.acg2e2hih2e2fa20.a2g7e2f2
		+a21.ag2ejkj2fdeaga20.f2gej2fd2e2ga20.2o4flm2eg2a20.a2l2f2lmnfga21.a2lf2l2mnf2a21.a2lmfm2nofa23.al3m4fna23.a7m2na23.an5m2na24.a2n4m2na25.a2n3mnoa25.anomnmoa26.3on4o26.aoq2
		+oroa26.a6srsa24.ap2qrs2rsa24.ap2qrsrsa26.a2qr3sa26.a2qr2sa27.aq2rsa28.aegsa29.aegsa28.a4tsa27.a4tvsa27.2a3sa53./50.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.a
		+cg2e2hih2ea22.a2g7ega23.ag2ekjkjka24.a2ge5ja22.2af2ge5ja21.a3l2fgkjk2ga20.a2l3m6fa20.a2l3m7f21.al3mf2lm2f2ea.a18.a4mf3mne3fafa17.an3mf3no2e2d3f17.a2n3m3f2g3edfga17.a2n3mn
		+ofa2g2e2ga16.aonomnmoa2.2agaga16.ap3on3oa4.a.a17.spqoq2osoa24.a6srsa25.ap2qr2sa27.a2q2rsa27.sp2qrs28.as2qra28.asega29.aseg2a28.as4ta27.as3tva28.a3sa52.
		// </art:creatures>
		"""

	/// A block is one line: "name|flips|colours|pixels" (16 x 16). The flips say how the land painter
	/// may vary the block from place to place so a wall of it is not wallpaper: "h" mirrored, "hv" also
	/// turned top to bottom, nothing for a block that must always be drawn as it is.
	static let tileText: String = """
		// <art:tiles> written by tools/art/build.py pack from tools/art/tiles: change the drawings, not this
		amethyst|hv|a8D8D97,bA3A3AD,c604180,d777783,eD8BDF2,f5C5C69,gFFFFFF,h996EC6|4a3b12abcb4a2d7acec2a2d2fc4afceghcad2fcecb2ace4hcadceghc2adc3hc4achc4adchc2b4ac7ac3b4ad3a2d3a2b2ac2dfd2a2fd5acecfd3adfcd3aceghc5acec2ace4hc2baceghcbac3hc3b2achc3bachcab5ac2ab3acd13ad2fd4a
		ashStone|hv|a493B47,b5B4A59,c3B2F3A,d2C212A|4a3b12a3b4a2c12a2c2dc4adc5ac2dc2ab2a2dc5a2c2a2b2acdc8a2b4ac3a2b13a3b4ac3a2c3a2b3a2cdc2a2dc6ac2dc3ac2dc5acdc5a2c6ac3a2b6ab6a3b5a3b5ab8ab3a2c13ac2dc4a
		birchLeaves|h|a779556,b97B26B,c617C46,d50693C|3a2b13a2b7ac13a3c2a2b4ac5ac2a2b4a3c2.13ac3.9ab4ad.3ac4a2b9a3ca2b11ac10a2b9ac4ab9a3c8ac2.3ac9a2c3.5a2b7ac2.4ab5a2b11ac2ab2a
		birchLog||a79736B,bFFFFFF,cE5E2D8,dBCB6AC,e3A3632|a2b10c2d2a2b2c3e5c2d2a2b10c2d2ab8c3e2d2a2b10c2d2a2b10c2d2ab3e8c2d2a2b10c2d2a2b5c2e3c2d2a2b10c2d2ab11c2d2a2bc2e7c2d2a2b8c2e2d2a2b10c2d2a2b5c3e2c2d2a2b10c2da
		birchLogBlock||a79736B,bFFFFFF,cE5E2D8,dBCB6AC,e3A3632|a2b10c2d2a2b2c3e5c2d2a2b10c2d2ab8c3e2d2a2b10c2d2a2b10c2d2ab3e8c2d2a2b10c2d2a2b5c2e3c2d2a2b10c2d2ab11c2d2a2bc2e7c2d2a2b8c2e2d2a2b10c2d2a2b5c3e2c2d2a2b10c2da
		brick||aB57363,b898583,cBE7E6A,d9E5F53,eA7685A,f824B44|7ab7cb7db7eb7fb7f17b3cb7ab4c3eb7db4e3fb7fb4f16b7ab7ab7db7db7fb7f17b3ab7cb4a3db7eb4d3fb7fb4f16b
		chest||a291F18,bC5A374,cA9895F,d856A46,e898D96,fD3BD68,gECE0A2,h685137|81.14a.a14b2a14c2a14d2a6e2f6e2a6cfg6c2a14c2acd10cdc2a14c2a14ha.14a.
		coal|hv|a8D8D97,bA3A3AD,c16161C,d777783,e4A4A55,f2A2A32,g5C5C69|4a3b12ab3c3a2d7ace2fc2d2gd4agdc5fcgd2cb2a2gdc4fcdcefc2adgda4c2ac2fc3ad3a2b4a2c4a2ca3b4ad3adcefc2b3a2dgd2agc3fc3ad3c3adgc2fc3ace2fc3a2d2c4ac5fc5ab4ac3fc5a3b4a3c7ab3a2d13ad2gd4a
		copper|hv|a8D8D97,bA3A3AD,c7F573D,d777783,eDAA77C,fB9825C,g5C5C69|4a3b11a3cb4a2d5ac2efc2a2dg2c4ace3fcadgcefcb2ac5fcadc2fcb2adc3fc4a2cb4ad3c2b13a3ba3cd3a2d3a2bac2efcd2a2g2c4ace4fcadcefc3ac5fc2ac2fc4ac4fc3a2cab4a4cb5a3b5ab8a2c2a2d9acefcd2gd4a
		crackedBrick||aA19080,b685A4E,cAB9989,d8A7969,e938272,f6D5E52|7ab7cb7db7eb7fb7f17b3cb7ab4c3eb7db4e3fb7fb4f16b7ab7ab7db7db7fb7f17b3ab7cb4a3db7eb4d3fb7fb4f16b
		crystalOre|hv|a5E6676,b72798B,c458288,d4D5464,eE5FAFA,f90DDD7,g3C4250|4a3b12a2b2c3a2d8acefc2d2gd4agdacefcd2gd2cb2a2gce2fca2dcefc2adgc2fc4acefc3ada2c2b2ace2fc6a3b2ac2fc2a2da2c2b3ad2cd2a2gcefc3ad2gd3adgcefc3a2cd5ace2fc2acefca2b2ac2fcb2acefc3b3a2c3bce2fcb8abac2fc13a2cgd4a
		deepRock|hv|a3E3945,b4E4857,c322D39,d25202C|4a3b12a3b4a2c12a2c2dc4adc5ac2dc2ab2a2dc5a2c2a2b2acdc8a2b4ac3a2b13a3b4ac3a2c3a2b3a2cdc2a2dc6ac2dc3ac2dc5acdc5a2c6ac3a2b6ab6a3b5a3b5ab8ab3a2c13ac2dc4a
		diamond|hv|a8D8D97,bA3A3AD,c42828D,d777783,eB6EDF1,f5C5C69,gFFFFFF,h6AC4C9|4a3b12abcb4a2d7acec2a2d2fc4afceghcad2fcecb2ace4hcadceghc2adc3hc4achc4adchc2b4ac7ac3b4ad3a2d3a2b2ac2dfd2a2fd5acecfd3adfcd3aceghc5acec2ace4hc2baceghcbac3hc3b2achc3bachcab5ac2ab3acd13ad2fd4a
		dirt|hv|a82614A,b70513E,c916F54,d5A4032,eA88A6A|6a2b10ac4a2b15ad3ac19a2b9a2b4abd4ae4a2b15ad7ac19a2b15abd2ac4a2b15abd22ae4ac22a2b5abd8a2b3a2b
		dryGrass|h|aCEC581,bB3A966,c928751,d70673E,e82614A,f70513E,g5A4032,h916F54,iA88A6A|2ab4ab4ab3aba4ba4ba22bc5bc6bcb3c3b2c5b3cde2cbcde2c2bcdcd3e3c3ed2cd7ed6ed12e2f15efg2eh4e2f15efg22ei4eh22e2f5efg8e2f3e2f
		emberOre|hv|a493B47,b5B4A59,c935940,d3B2F3A,eDFC178,fD28D5D,g2C212A|4a3b11a3cb4a2d5ac2efc2a2dg2c4ace3fcadgcefcb2ac5fcadc2fcb2adc3fc4a2cb4ad3c2b13a3ba3cd3a2d3a2bac2efcd2a2g2c4ace4fcadcefc3ac5fc2ac2fc4ac4fc3a2cab4a4cb5a3b5ab8a2c2a2d9acefcd2gd4a
		flowerR||a1C1820,bC96763,cE1897E,dDFCB78,e5E9A51,f3E733F|54.2a13.a2ba11.ab2cba9.abc2dcba9.ab2cba11.a2ba13.aea.2a8.3ae2a2ea6.a2eaeaefa8.af3e2a10.afea13.aea13.aea7.
		flowerY||a1C1820,bCDB25F,cE4D486,dBE9056,e5E9A51,f3E733F|54.2a13.a2ba11.ab2cba9.abc2dcba9.ab2cba11.a2ba13.aea.2a8.3ae2a2ea6.a2eaeaefa8.af3e2a10.afea13.aea13.aea7.
		furnace||a777783,bA3A3AD,c5C5C69,d221D24,eC37756,fD49E61,gDCBF71,hEEE3A8,i8D8D97|.14a.a14b2ab12ac2aba10cac2abac8dcac2abac2d5edcac2abacdef2gfedcac2abacdeg2hgedcac2abac2de2fe2dcac2abac8dcac2aba10cac2ab12ac2abaididididi2ac2abaididididi2ac2a14ca.14a.
		gold|hv|a8D8D97,bA3A3AD,c967B45,d777783,eFFFFFF,fE9DB96,gCFB764,h5C5C69|4a3b12a2cb4ade6acfgc2a2defe4ahc2gc2ad2he2ab2a2h2c4a2d2a2b2adhd5a2ca2b4ad3a2bcfgc5ae3a3bc3gc3aefe2a2b2ac2gcd2ahed6ad2cd3ad2hd2c3adhd5a2dcfgc2ad2a2cb4ac3gc3acfgc5a3c4ac2gc6ab3a2da2c10ad2hd4a
		grass|h|a8BAF65,b66924F,c497341,d345734,e82614A,f70513E,g5A4032,h916F54,iA88A6A|2ab4ab4ab3aba4ba4ba22bc5bc6bcb3c3b2c5b3cde2cbcde2c2bcdcd3e3c3ed2cd7ed6ed12e2f15efg2eh4e2f15efg22ei4eh22e2f5efg8e2f3e2f
		iron|hv|a8D8D97,bA3A3AD,c7B5B50,d777783,eDDBEA2,fBB967D,g5C5C69|4a3b10a4cb4a2d5ac2efc2a2d2g2c3ace3fcad2gcefc2agc3fc2adce2fc2adg3c4ac2fc4ad3a2b3a2c8a3b4ad3a2d2a4c2a2dgd2a2gdc2e2fcd2gd2cad2gce3fcdgdcefca2dac4fc2ac2fc5a4c3ab2c2a2ca3b5ab3acefcab3a2d5ac2fc4ad2gd4a
		jungleGrass|h|a79C470,b519C57,c3A7547,d2A5537,e534234,f46372A,g372A21,h61513F,i6A5A48|2ab4ab4ab3aba4ba4ba22bc5bc6bcb3c3b2c5b3cde2cbcde2c2bcdcd3e3c3ed2cd7ed6ed12e2f15efg2eh4e2f15efg22ei4eh22e2f5efg8e2f3e2f
		jungleLeaves|h|a43804D,b659B58,c366840,d2D5636|3a2b13a2b7ac13a3c2a2b4ac5ac2a2b4a3c2.13ac3.9ab4ad.3ac4a2b9a3ca2b11ac10a2b9ac4ab9a3c8ac2.3ac9a2c3.5a2b7ac2.4ab5a2b11ac2ab2a
		jungleLog||a2F2819,b7E6E4A,c625438,d463B26,e493F2A|a2b2cd3cd2c3e2a2b2cd6cd2e2ab7cd2cd2e2a2bcd4cd3c2e2a2bcd8c2e2a2bcd2cd4cd2e2ab5cd4cd2e2a2b4cd2cd2c2e2a2b2cd4cd2c2e2a2b2cd7c2e2ab3cd2cd3cd2e2a2b5cd3cd2e2a2bcd3cd4c2e2a2bcd6cdc2e2ab5cd3cdc2e2a2b4cd5c2ea
		jungleLogBlock||a2F2819,b7E6E4A,c625438,d463B26,e493F2A|a2b2cd3cd2c3e2a2b2cd6cd2e2ab7cd2cd2e2a2bcd4cd3c2e2a2bcd8c2e2a2bcd2cd4cd2e2ab5cd4cd2e2a2b4cd2cd2c2e2a2b2cd4cd2c2e2a2b2cd7c2e2ab3cd2cd3cd2e2a2b5cd3cd2e2a2bcd3cd4c2e2a2bcd6cdc2e2ab5cd3cdc2e2a2b4cd5c2ea
		leaves|h|a557F47,b739C59,c42663B,d365733|3a2b13a2b7ac13a3c2a2b4ac5ac2a2b4a3c2.13ac3.9ab4ad.3ac4a2b9a3ca2b11ac10a2b9ac4ab9a3c8ac2.3ac9a2c3.5a2b7ac2.4ab5a2b11ac2ab2a
		log||a3C2C21,b907253,c735840,d58412F,e5A4332|a2b2cd3cd2c3e2a2b2cd6cd2e2ab7cd2cd2e2a2bcd4cd3c2e2a2bcd8c2e2a2bcd2cd4cd2e2ab5cd4cd2e2a2b4cd2cd2c2e2a2b2cd4cd2c2e2a2b2cd7c2e2ab3cd2cd3cd2e2a2b5cd3cd2e2a2bcd3cd4c2e2a2bcd6cdc2e2ab5cd3cdc2e2a2b4cd5c2ea
		logBlock||a3C2C21,b907253,c735840,d58412F,e5A4332|a2b2cd3cd2c3e2a2b2cd6cd2e2ab7cd2cd2e2a2bcd4cd3c2e2a2bcd8c2e2a2bcd2cd4cd2e2ab5cd4cd2e2a2b4cd2cd2c2e2a2b2cd4cd2c2e2a2b2cd7c2e2ab3cd2cd3cd2e2a2b5cd3cd2e2a2bcd3cd4c2e2a2bcd6cdc2e2ab5cd3cdc2e2a2b4cd5c2ea
		mossBrick||a8BA174,b4D5C41,c96AC7E,d73885F,e7D9269,f576B4A|7ab7cb7db7eb7fb7f17b3cb7ab4c3eb7db4e3fb7fb4f16b7ab7ab7db7db7fb7f17b3ab7cb4a3db7eb4d3fb7fb4f16b
		mossGrass|h|a96A765,b75884D,c586A3B,d3E4D2D,e534234,f46372A,g372A21,h61513F,i6A5A48|2ab4ab4ab3aba4ba4ba22bc5bc6bcb3c3b2c5b3cde2cbcde2c2bcdcd3e3c3ed2cd7ed6ed12e2f15efg2eh4e2f15efg22ei4eh22e2f5efg8e2f3e2f
		mud|hv|a534234,b46372A,c61513F,d372A21,e6A5A48|6a2b10ac4a2b15ad3ac19a2b9a2b4abd4ae4a2b15ad7ac19a2b15abd2ac4a2b15abd22ae4ac22a2b5abd8a2b3a2b
		mythril|hv|a8D8D97,bA3A3AD,c534B98,d777783,eB5ADEF,f7F76DE,g5C5C69|4a3b12a2b2c3a2d8acefc2d2gd4agdacefcd2gd2cb2a2gce2fca2dcefc2adgc2fc4acefc3ada2c2b2ace2fc6a3b2ac2fc2a2da2c2b3ad2cd2a2gcefc3ad2gd3adgcefc3a2cd5ace2fc2acefca2b2ac2fcb2acefc3b3a2c3bce2fcb8abac2fc13a2cgd4a
		palmLog||a5A4733,bB2966E,c957B58,d776043,e7D6549|a2b2cd3cd2c3e2a2b2cd6cd2e2ab7cd2cd2e2a2bcd4cd3c2e2a2bcd8c2e2a2bcd2cd4cd2e2ab5cd4cd2e2a2b4cd2cd2c2e2a2b2cd4cd2c2e2a2b2cd7c2e2ab3cd2cd3cd2e2a2b5cd3cd2e2a2bcd3cd4c2e2a2bcd6cdc2e2ab5cd3cdc2e2a2b4cd5c2ea
		palmLogBlock||a5A4733,bB2966E,c957B58,d776043,e7D6549|a2b2cd3cd2c3e2a2b2cd6cd2e2ab7cd2cd2e2a2bcd4cd3c2e2a2bcd8c2e2a2bcd2cd4cd2e2ab5cd4cd2e2a2b4cd2cd2c2e2a2b2cd4cd2c2e2a2b2cd7c2e2ab3cd2cd3cd2e2a2b5cd3cd2e2a2bcd3cd4c2e2a2bcd6cdc2e2ab5cd3cdc2e2a2b4cd5c2ea
		pineLeaves|h|a3B6554,b558469,c305345,d27463A|3a2b13a2b7ac13a3c2a2b4ac5ac2a2b4a3c2.13ac3.9ab4ad.3ac4a2b9a3ca2b11ac10a2b9ac4ab9a3c8ac2.3ac9a2c3.5a2b7ac2.4ab5a2b11ac2ab2a
		planks||aC7A87D,b765C40,cB19068,d56402D,e9C7E58|5ab10a4cdb4c3e4c3ecb10c16b12ab3a3c3e5cdb11c2e2cb3c16b2ab13acdb4c3e8cb9c3ec16b9ab6a2c3e3cdb15cb2c3ec16b
		saltpeter|hv|a8D8D97,bA3A3AD,c88857B,d777783,eFFFFFF,fD9D5CA,g5C5C69|4a3b11a5c3a2d5ac2e4fcd2gd4ag6cd2gd2cb2a2gd5ad2cefc2adgd4a2c2e2fc3ad3abce4f2c6a3b5c3a2d3a2b3a2dgd2a2gd4c2ad2gd3adgc2e2f2cdgd5ace6fc3a2c3a7c2a2cefc4a3b3ace3fc5ab3a2d4c9ad2gd4a
		sand|hv|aD6C590,bE5D7A7,cAF9869,dC6B27C|18a5b7ac4a4d3a3b5ac7a3d19a3b5ac4a3b3d10a3d6a4b7ac4a4d2ac22a3b13a3d5ac14a4b2ac9a4d6a3b7ac5a3d9a
		sandstone|hv|aC3AD7C,bD3BF8F,cB09A6B,d998459|4a3b12a3b4a2c12a2c2dc4adc5ac2dc2ab2a2dc5a2c2a2b2acdc8a2b4ac3a2b13a3b4ac3a2c3a2b3a2cdc2a2dc6ac2dc3ac2dc5acdc5a2c6ac3a2b6ab6a3b5a3b5ab8ab3a2c13ac2dc4a
		silver|hv|a8D8D97,bA3A3AD,c777783,d6A7381,eFFFFFF,fC2C9D5,g5C5C69|4a3b12a3b4ac2d11ac2defd3agc4a2de2fdab2a2gca2de2fd2a2b2acgcde2fd3a2b4acadfdb13ad2b4a2d2a2c3a2b3a2ded2a2gc5a2defd3acg2d2a2de2fd5adef2de2fd3a2b2adf2e2fd4a3b3a5d5ab8ab3a2c13ac2gc4a
		slate|hv|a5E6676,b72798B,c4D5464,d3C4250|4a3b12a3b4a2c12a2c2dc4adc5ac2dc2ab2a2dc5a2c2a2b2acdc8a2b4ac3a2b13a3b4ac3a2c3a2b3a2cdc2a2dc6ac2dc3ac2dc5acdc5a2c6ac3a2b6ab6a3b5a3b5ab8ab3a2c13ac2dc4a
		snow|hv|aF0F6FC,bFFFFFF,cC1D1E6,dD8E4F3|18a5b7ac4a4d3a3b5ac7a3d19a3b5ac4a3b3d10a3d6a4b7ac4a4d2ac22a3b13a3d5ac14a4b2ac9a4d6a3b7ac5a3d9a
		stone|hv|a8D8D97,bA3A3AD,c777783,d5C5C69|4a3b12a3b4a2c12a2c2dc4adc5ac2dc2ab2a2dc5a2c2a2b2acdc8a2b4ac3a2b13a3b4ac3a2c3a2b3a2cdc2a2dc6ac2dc3ac2dc5acdc5a2c6ac3a2b6ab6a3b5a3b5ab8ab3a2c13ac2dc4a
		tallGrass||a8BAF65,b66924F,c497341|114.a9.a5.b3.a5.ba3.ab2.ab2.a2.ab3.ab2.ab.ab.a2b.2a2ba.2b.ab.a2baba3ba2ba2ba21bc2bc2bc3bc2bc2b16c
		tin|hv|a8D8D97,bA3A3AD,c7D8691,d777783,eF1F5F8,fC6CFD7,g5C5C69|4a3b11a3cb4a2d5ac2efc2a2dg2c4ace3fcadgcefcb2ac5fcadc2fcb2adc3fc4a2cb4ad3c2b13a3ba3cd3a2d3a2bac2efcd2a2g2c4ace4fcadcefc3ac5fc2ac2fc4ac4fc3a2cab4a4cb5a3b5ab8a2c2a2d9acefcd2gd4a
		torch||a1C1820,bE2CD81,cEEE3A8,dFFFFFF,eD49E61,f8E6E4D,g684E37|23.a14.aba12.abcba11.abdcba9.aec2dcea8.aecd2cea9.ae2cea11.a2ea12.afga12.afga12.afga12.afga12.afga12.afga12.afga6.
		voidOre|hv|a493B47,b5B4A59,c65418B,d3B2F3A,eE0B2F0,fAB6FDB,g2C212A|4a3b12a2b2c3a2d8acefc2d2gd4agdacefcd2gd2cb2a2gce2fca2dcefc2adgc2fc4acefc3ada2c2b2ace2fc6a3b2ac2fc2a2da2c2b3ad2cd2a2gcefc3ad2gd3adgcefc3a2cd5ace2fc2acefca2b2ac2fcb2acefc3b3a2c3bce2fcb8abac2fc13a2cgd4a
		workbench||a98A0AD,bCED4DD,c898D96,dC2C8D1,e9C7E58,fC7A87D,gB19068,h765C40|52.ab5.3c5.a2ba4.cdc6.2e6.e3.16f16g16h.eh10.eh2.eh.8e.eh2.eh.8h.eh2.eh10.eh2.eh10.eh2.eh10.eh2.eh10.eh.
		// </art:tiles>
		"""

	/// Colours of a picture: "aF0A0B0,b1E1418" gives each letter its colour
	static func palette(_ s: Substring) -> [UInt8: UInt32] {
		var out: [UInt8: UInt32] = [:]
		for e in s.split(separator: ",") {
			guard let k = e.utf8.first, let v = UInt32(e.dropFirst(), radix: 16) else { continue }
			out[k] = v
		}
		return out
	}

	/// Unpacks one picture of w x h pixels
	static func unpack(_ s: Substring, _ w: Int, _ h: Int, _ pal: [UInt8: UInt32]) -> PixelBuf {
		var b = PixelBuf(w: w, h: h)
		var lut: [UInt32] = [UInt32](repeating: 0, count: 128)
		for (k, v) in pal where k < 128 { lut[Int(k)] = 0xFF000000 | v }
		let n: Int = w * h
		var i: Int = 0
		var run: Int = 0
		for c in s.utf8 {
			if c >= 48 && c <= 57 {
				run = run * 10 + Int(c) - 48
				continue
			}
			let count: Int = max(1, run)
			run = 0
			let v: UInt32 = c == 46 ? 0 : lut[Int(c & 127)]
			var k: Int = 0
			while k < count && i < n {
				b.px[i] = v
				i += 1
				k += 1
			}
		}
		return b
	}
}

/// One creature's drawing as ArtSheet keeps it (its frames are unpacked when first asked for)
struct SheetArt {
	var w: Int
	var h: Int
	var foot: Int
	var cx: Double
	var pal: [UInt8: UInt32]
	var poses: [String: [Int]]
	var packed: [Substring]
}

enum CreatureSheet {
	static let arts: [String: SheetArt] = parse(ArtSheet.creatureText)

	static func parse(_ s: String) -> [String: SheetArt] {
		var out: [String: SheetArt] = [:]
		var name: String = ""
		var cur: SheetArt? = nil
		var body: String = ""
		func close() {
			guard var a = cur else { return }
			a.packed = Substring(body).split(separator: "/")
			out[name] = a
			cur = nil
			body = ""
		}
		for raw in s.split(separator: "\n") {
			let line: Substring = raw.drop(while: { (c: Character) -> Bool in c == "\t" || c == " " })
			if line.isEmpty || line.hasPrefix("//") { continue }
			if line.hasPrefix("+") {
				body.append(contentsOf: line.dropFirst())
				continue
			}
			close()
			let f: [Substring] = line.split(separator: "|", omittingEmptySubsequences: false)
			guard f.count >= 7, let w = Int(f[1]), let h = Int(f[2]), let foot = Int(f[3]), let cx = Double(f[4]) else { continue }
			var poses: [String: [Int]] = [:]
			for e in f[6].split(separator: ";") {
				let kv: [Substring] = e.split(separator: ":")
				if kv.count != 2 { continue }
				poses[String(kv[0])] = kv[1].split(separator: ",").compactMap { Int($0) }
			}
			name = String(f[0])
			cur = SheetArt(w: w, h: h, foot: foot, cx: cx, pal: ArtSheet.palette(f[5]), poses: poses, packed: [])
		}
		close()
		return out
	}

	static func has(_ name: String) -> Bool { return arts[name] != nil }

	/// A drawing's frames, unpacked
	static func frames(_ name: String) -> [PixelBuf] {
		guard let a = arts[name] else { return [] }
		return a.packed.map { ArtSheet.unpack($0, a.w, a.h, a.pal) }
	}

	/// How a drawing's frames are used: its poses by name
	static func anim(_ a: SheetArt) -> CreatureAnim {
		var an = CreatureAnim()
		an.walk = a.poses["walk"] ?? []
		if let x = a.poses["alt"]?.first { an.idleAlt = x }
		if let x = a.poses["strike"]?.first { an.attack = x }
		if let x = a.poses["hop"]?.first {
			an.hop = true
			an.hopFrame = x
		}
		if let c = a.poses["fly"] { an.cycle = c }
		for (k, v) in a.poses {
			if let f0 = v.first { an.poses[k] = f0 }
		}
		return an
	}

	/// A creature's look from its drawing (nil when it has not been drawn by hand yet)
	static func look(_ name: String) -> CreatureLook? {
		guard let a = arts[name], !a.packed.isEmpty else { return nil }
		return CreatureLook(frames: frames(name), anim: anim(a), scale: fineScale, foot: a.foot + 1, cx: a.cx, fine: true)
	}
}

/// The hand-drawn blocks, by tile number
enum TileSheet {
	static let parsed: ([UInt8: PixelBuf], [UInt8: Int]) = parse(ArtSheet.tileText)
	static var bufs: [UInt8: PixelBuf] { return parsed.0 }
	/// how each may be varied from place to place: bit 1 mirrored, bit 2 turned top to bottom
	static var flips: [UInt8: Int] { return parsed.1 }

	static func parse(_ s: String) -> ([UInt8: PixelBuf], [UInt8: Int]) {
		var byName: [String: Tile] = [:]
		for t in Tile.allCases { byName[String(describing: t)] = t }
		var out: [UInt8: PixelBuf] = [:]
		var fl: [UInt8: Int] = [:]
		for raw in s.split(separator: "\n") {
			let line: Substring = raw.drop(while: { (c: Character) -> Bool in c == "\t" || c == " " })
			if line.isEmpty || line.hasPrefix("//") { continue }
			let f: [Substring] = line.split(separator: "|", omittingEmptySubsequences: false)
			guard f.count >= 4, let t = byName[String(f[0])] else { continue }
			out[t.rawValue] = ArtSheet.unpack(f[3], tileArtPx, tileArtPx, ArtSheet.palette(f[2]))
			fl[t.rawValue] = (f[1].contains("h") ? 1 : 0) | (f[1].contains("v") ? 2 : 0)
		}
		return (out, fl)
	}
}

// ===== p13a_mobdefs =====

// MARK: - Mob definitions

enum MobKind: Int, Codable, CaseIterable {
	case pig, cow, sheep, chicken, crow, giraffe, frog, fish
	case elephant, bear, grizzly, polarBear, tiger, wolf, cat
	case zombie, skeleton, slime, bat, scorpion, wraith
	case villager, pirate, pirateGunner, pirateCaptain
	case imp, emberSlime, cinderBat
	case bearBoss, rex
	/// appended, so saved creature kinds keep their numbers
	case crawler, golem, archer, sentinel, mimic, warden
	/// a creature from a player's mod (which one: `Mob.cslot`, see ModRuntime)
	case custom

	/// wild hunters that roam by day as well: they have their own small number in the spawner, so
	/// they never use up the night's monsters
	var isPredator: Bool { return self == .grizzly || self == .polarBear || self == .tiger || self == .scorpion }

	/// monsters run by `think` (senses, memory, chase, search, return) around their own attacks
	var thinks: Bool {
		switch self {
		case .zombie, .skeleton, .pirate, .pirateCaptain, .pirateGunner, .imp, .slime, .emberSlime,
			 .bat, .cinderBat, .wraith, .crawler, .golem, .archer, .custom: return true
		default: return false
		}
	}
}

enum Behavior: Int {
	case passive, skittish, defensive, hostile, ranged, flyer, swimmer, boss
}

struct MobDef {
	var name: String
	var w: Double
	var h: Double
	var hp: Double
	var speed: Double
	var dmg: Double
	var behavior: Behavior
	var flying: Bool = false
	var aggro: Double = 14
	var jump: Double = 12
	var hostile: Bool = false
}

/// Mob definitions are built once into a table: building a MobDef (it holds a String) on every
/// lookup was one of the hottest calls in the AI loop in debug builds.
var mobDefTable: [MobDef] = MobKind.allCases.map { makeMobDef($0) }

@inline(__always) func mobDef(_ k: MobKind) -> MobDef { return mobDefTable[k.rawValue] }

func makeMobDef(_ k: MobKind) -> MobDef {
	switch k {
	case .pig: return MobDef(name: "Pig", w: 0.9, h: 0.7, hp: 10, speed: 1.6, dmg: 0, behavior: .passive)
	case .cow: return MobDef(name: "Cow", w: 1.3, h: 1.1, hp: 14, speed: 1.4, dmg: 0, behavior: .passive)
	case .sheep: return MobDef(name: "Sheep", w: 1.1, h: 0.95, hp: 12, speed: 1.5, dmg: 0, behavior: .passive)
	case .chicken: return MobDef(name: "Chicken", w: 0.6, h: 0.6, hp: 5, speed: 1.8, dmg: 0, behavior: .skittish)
	case .crow: return MobDef(name: "Crow", w: 0.6, h: 0.5, hp: 4, speed: 3.6, dmg: 0, behavior: .flyer, flying: true)
	case .giraffe: return MobDef(name: "Giraffe", w: 1.6, h: 3.2, hp: 30, speed: 3.4, dmg: 0, behavior: .skittish)
	case .frog: return MobDef(name: "Frog", w: 0.5, h: 0.4, hp: 3, speed: 2.0, dmg: 0, behavior: .skittish, jump: 9)
	case .fish: return MobDef(name: "Fish", w: 0.7, h: 0.4, hp: 3, speed: 2.2, dmg: 0, behavior: .swimmer)
	case .elephant: return MobDef(name: "Elephant", w: 2.8, h: 2.4, hp: 80, speed: 2.4, dmg: 7, behavior: .defensive, aggro: 10)
	case .bear: return MobDef(name: "Brown Bear", w: 1.8, h: 1.2, hp: 42, speed: 2.8, dmg: 5, behavior: .defensive, aggro: 11)
	case .grizzly: return MobDef(name: "Grizzly Bear", w: 2.0, h: 1.4, hp: 70, speed: 3.4, dmg: 7, behavior: .hostile, aggro: 12, hostile: true)
	case .polarBear: return MobDef(name: "Polar Bear", w: 2.0, h: 1.4, hp: 64, speed: 3.2, dmg: 7, behavior: .hostile, aggro: 12, hostile: true)
	case .tiger: return MobDef(name: "Tiger", w: 1.7, h: 1.0, hp: 48, speed: 4.6, dmg: 6, behavior: .hostile, aggro: 14, jump: 15, hostile: true)
	case .wolf: return MobDef(name: "Wolf", w: 1.2, h: 0.9, hp: 24, speed: 4.0, dmg: 3, behavior: .defensive, aggro: 11, jump: 14)
	case .cat: return MobDef(name: "Cat", w: 0.7, h: 0.6, hp: 10, speed: 3.0, dmg: 0, behavior: .skittish, jump: 13)
	case .zombie: return MobDef(name: "Zombie", w: 0.7, h: 1.7, hp: 30, speed: 1.8, dmg: 4, behavior: .hostile, aggro: 16, hostile: true)
	case .skeleton: return MobDef(name: "Skeleton Knight", w: 0.7, h: 1.8, hp: 38, speed: 2.1, dmg: 5, behavior: .hostile, aggro: 15, hostile: true)
	case .slime: return MobDef(name: "Slime", w: 0.9, h: 0.7, hp: 18, speed: 2.6, dmg: 3, behavior: .hostile, aggro: 12, jump: 11, hostile: true)
	case .bat: return MobDef(name: "Cave Bat", w: 0.6, h: 0.4, hp: 6, speed: 4.2, dmg: 2, behavior: .flyer, flying: true, aggro: 12, hostile: true)
	case .scorpion: return MobDef(name: "Scorpion", w: 1.2, h: 0.6, hp: 26, speed: 2.6, dmg: 4, behavior: .hostile, aggro: 11, hostile: true)
	case .wraith: return MobDef(name: "Wraith", w: 0.9, h: 1.5, hp: 44, speed: 2.8, dmg: 6, behavior: .flyer, flying: true, aggro: 18, hostile: true)
	case .villager: return MobDef(name: "Villager", w: 0.7, h: 1.7, hp: 20, speed: 1.4, dmg: 0, behavior: .passive)  // retired: never spawns
	case .pirate: return MobDef(name: "Pirate", w: 0.7, h: 1.8, hp: 48, speed: 2.5, dmg: 6, behavior: .hostile, aggro: 20, hostile: true)
	case .pirateGunner: return MobDef(name: "Pirate Gunner", w: 0.7, h: 1.8, hp: 40, speed: 1.9, dmg: 5, behavior: .ranged, aggro: 20, hostile: true)
	case .pirateCaptain: return MobDef(name: "Pirate Captain", w: 0.8, h: 1.9, hp: 140, speed: 2.5, dmg: 8, behavior: .hostile, aggro: 22, hostile: true)
	case .imp: return MobDef(name: "Umbral Imp", w: 0.7, h: 1.5, hp: 34, speed: 2.6, dmg: 5, behavior: .ranged, aggro: 18, hostile: true)
	case .emberSlime: return MobDef(name: "Ember Slime", w: 1.0, h: 0.8, hp: 36, speed: 2.8, dmg: 5, behavior: .hostile, aggro: 12, jump: 12, hostile: true)
	case .cinderBat: return MobDef(name: "Cinder Bat", w: 0.6, h: 0.4, hp: 14, speed: 4.6, dmg: 4, behavior: .flyer, flying: true, aggro: 14, hostile: true)
	case .bearBoss: return MobDef(name: "Ursavor, Warden of the Gate", w: 5.2, h: 3.9, hp: 900, speed: 3.0, dmg: 10, behavior: .boss, aggro: 60, hostile: true)
	case .rex: return MobDef(name: "Tyrannax the Bonecrown", w: 7.0, h: 4.4, hp: 1400, speed: 3.4, dmg: 13, behavior: .boss, aggro: 60, hostile: true)
	case .crawler: return MobDef(name: "Cave Crawler", w: 1.1, h: 0.6, hp: 22, speed: 4.4, dmg: 4, behavior: .hostile, aggro: 13, jump: 11.5, hostile: true)
	case .golem: return MobDef(name: "Stone Golem", w: 1.5, h: 2.2, hp: 150, speed: 1.15, dmg: 8, behavior: .hostile, aggro: 12, jump: 9, hostile: true)
	case .archer: return MobDef(name: "Bow Zombie", w: 0.7, h: 1.7, hp: 30, speed: 2.3, dmg: 4, behavior: .ranged, aggro: 20, hostile: true)
	case .sentinel: return MobDef(name: "Crystal Sentinel", w: 1.4, h: 2.0, hp: 320, speed: 3.0, dmg: 7, behavior: .boss, flying: true, aggro: 30, hostile: true)
	case .mimic: return MobDef(name: "Mimic", w: 1.0, h: 0.95, hp: 90, speed: 3.2, dmg: 7, behavior: .hostile, aggro: 16, jump: 12, hostile: true)
	case .warden: return MobDef(name: "The Hollow Warden", w: 3.0, h: 4.6, hp: 2200, speed: 2.6, dmg: 11, behavior: .boss, flying: true, aggro: 60, hostile: true)
	case .custom: return MobDef(name: "Custom Creature", w: 0.8, h: 1.6, hp: 20, speed: 2, dmg: 4, behavior: .hostile, hostile: true)
	}
}

// MARK: - Drops

func mobDrops(_ k: MobKind, _ rng: inout RNG, _ sheared: Bool) -> [Stack] {
	var out: [Stack] = []
	func add(_ it: Item, _ lo: Int, _ hi: Int, _ p: Double) {
		if rng.double() < p { out.append(Stack(item: it, count: lo + rng.int(max(1, hi - lo + 1)))) }
	}
	switch k {
	case .pig: add(.food(.rawMeat), 1, 3, 1.0)
	case .cow: add(.food(.rawMeat), 2, 4, 1.0); add(.mat(.leather), 1, 2, 0.8)
	case .sheep: add(.food(.rawMeat), 1, 2, 1.0); if !sheared { add(.mat(.wool), 1, 3, 0.9) }
	case .chicken: add(.food(.rawMeat), 1, 1, 0.9); add(.mat(.feather), 1, 3, 0.9)
	case .crow: add(.mat(.feather), 1, 2, 0.8)
	case .giraffe: add(.food(.rawMeat), 2, 4, 1.0); add(.mat(.leather), 2, 4, 0.9)
	case .frog: add(.mat(.string), 0, 1, 0.1)
	case .fish: add(.food(.rawFish), 1, 1, 1.0)
	case .elephant: add(.food(.rawMeat), 4, 7, 1.0); add(.mat(.tusk), 1, 2, 0.8); add(.mat(.leather), 2, 4, 0.9)
	case .bear: add(.food(.rawMeat), 2, 4, 1.0); add(.mat(.fur), 1, 3, 0.9); add(.mat(.claw), 1, 1, 0.3)
	case .grizzly: add(.food(.rawMeat), 3, 5, 1.0); add(.mat(.fur), 2, 4, 1.0); add(.mat(.claw), 1, 2, 0.6)
	case .polarBear: add(.food(.rawMeat), 3, 5, 1.0); add(.mat(.fur), 2, 4, 1.0); add(.mat(.claw), 1, 2, 0.5)
	case .tiger: add(.food(.rawMeat), 2, 4, 1.0); add(.mat(.leather), 1, 3, 0.9); add(.mat(.claw), 1, 2, 0.6)
	case .wolf: add(.food(.rawMeat), 1, 2, 0.9); add(.mat(.fur), 1, 2, 0.6); add(.mat(.bone), 1, 2, 0.4)
	case .cat: add(.mat(.string), 1, 2, 0.5)
	case .zombie: add(.food(.rawMeat), 0, 1, 0.3); add(.mat(.string), 0, 2, 0.3); add(.food(.carrot), 1, 1, 0.08); add(.mat(.ironBar), 1, 1, 0.04)
	case .skeleton: add(.mat(.bone), 1, 3, 0.9); add(.ammo(.arrow), 2, 6, 0.5); add(.sword(.stone), 1, 1, 0.06); add(.mat(.coal), 1, 3, 0.4)
	case .slime: add(.mat(.string), 1, 2, 0.4); add(.block(.torch), 1, 3, 0.3)
	case .bat: add(.mat(.string), 0, 1, 0.2)
	case .scorpion: add(.mat(.claw), 1, 1, 0.5); add(.food(.rawMeat), 1, 1, 0.5)
	case .wraith: add(.mat(.mythrilOre), 1, 2, 0.4); add(.mat(.goldBar), 1, 2, 0.3)
	case .villager: break
	case .pirate: add(.mat(.goldBar), 1, 2, 0.5); add(.ammo(.bullet), 2, 6, 0.4); add(.mat(.gunpowder), 1, 3, 0.5); add(.sword(.iron), 1, 1, 0.1); add(.gadget(.bomb), 1, 2, 0.15)
	case .pirateGunner: add(.mat(.goldBar), 1, 2, 0.5); add(.ammo(.bullet), 3, 8, 0.7); add(.mat(.gunpowder), 1, 4, 0.7); add(.gun(.pistol), 1, 1, 0.12)
	case .pirateCaptain: add(.mat(.goldBar), 4, 8, 1.0); add(.mat(.diamond), 1, 3, 0.8); add(.gun(.rifle), 1, 1, 0.4); add(.ammo(.bullet), 8, 16, 1.0)
	case .imp: add(.mat(.emberOre), 1, 2, 0.5); add(.mat(.coal), 2, 4, 0.6)
	case .emberSlime: add(.mat(.emberOre), 1, 3, 0.6); add(.block(.torch), 2, 5, 0.5)
	case .cinderBat: add(.mat(.emberOre), 0, 1, 0.3)
	case .bearBoss:
		add(.mat(.fur), 6, 10, 1.0); add(.mat(.claw), 3, 5, 1.0); add(.mat(.goldBar), 6, 12, 1.0)
		add(.mat(.diamond), 3, 6, 1.0); add(.food(.cookedMeat), 6, 10, 1.0)
		add(.armor(.chest, .gold), 1, 1, 0.5)
	case .rex:
		add(.mat(.bone), 10, 20, 1.0); add(.mat(.tusk), 2, 4, 1.0); add(.mat(.goldBar), 6, 12, 1.0)
		add(.mat(.mythrilBar), 2, 5, 1.0); add(.food(.cookedMeat), 6, 10, 1.0)
	case .crawler: add(.mat(.string), 1, 3, 0.8); add(.mat(.claw), 1, 1, 0.25)
	case .golem:
		add(.block(.stone), 4, 8, 1.0); add(.mat(.ironOre), 1, 3, 0.6); add(.mat(.crystalShard), 1, 2, 0.35)
		add(.mat(.relicFragment), 1, 1, 0.1)
	case .archer: add(.food(.rawMeat), 0, 1, 0.3); add(.mat(.string), 0, 2, 0.4); add(.ammo(.arrow), 3, 8, 0.8); add(.bow, 1, 1, 0.05)
	case .sentinel:
		add(.mat(.crystalShard), 8, 14, 1.0); add(.mat(.diamond), 2, 4, 1.0); add(.block(.glowCrystal), 4, 8, 1.0)
		add(.mat(.relicFragment), 2, 3, 1.0); add(.gear(.headlamp), 1, 1, 0.35)
	case .mimic: add(.mat(.goldBar), 2, 5, 1.0); add(.mat(.relicFragment), 1, 1, 0.8); add(.mat(.diamond), 1, 2, 0.35)
	case .warden:
		add(.mat(.umbralHeart), 1, 1, 1.0); add(.mat(.voidBar), 6, 10, 1.0); add(.mat(.diamond), 4, 8, 1.0)
		add(.mat(.emberBar), 4, 8, 1.0); add(.mat(.relicFragment), 3, 3, 1.0)
	case .custom:
		// a custom creature's drops come from its mod (see dropModLoot)
		break
	}
	return out
}

// MARK: - Spawn rules

enum SpawnPlace { case surface, cave, ocean, umbral }
enum SpawnWhen { case any, day, night }

struct SpawnRule {
	var kind: MobKind
	var weight: Double
	var place: SpawnPlace
	var when: SpawnWhen
	var biomes: [Biome]
	var group: Int
	var minY: Int = 0
	var maxY: Int = 9999
	/// a custom creature's slot (-1 for the game's creatures), how many of it may be about at once, and
	/// whether it appears high in the sky
	var slot: Int = -1
	var maxNearby: Int = 99
	var sky: Bool = false
}

let spawnRules: [SpawnRule] = [
	// surface, passive and wild animals by biome
	SpawnRule(kind: .pig, weight: 5, place: .surface, when: .any, biomes: [.plains, .forest], group: 2),
	SpawnRule(kind: .cow, weight: 5, place: .surface, when: .any, biomes: [.plains, .forest], group: 2),
	SpawnRule(kind: .sheep, weight: 5, place: .surface, when: .any, biomes: [.plains, .forest, .mountain], group: 3),
	SpawnRule(kind: .chicken, weight: 4, place: .surface, when: .day, biomes: [.plains, .forest, .savanna], group: 3),
	SpawnRule(kind: .crow, weight: 3, place: .surface, when: .any, biomes: [.plains, .forest, .desert, .savanna, .swamp, .mountain], group: 2),
	SpawnRule(kind: .giraffe, weight: 5, place: .surface, when: .any, biomes: [.savanna], group: 2),
	SpawnRule(kind: .elephant, weight: 3, place: .surface, when: .any, biomes: [.savanna, .jungle], group: 1),
	SpawnRule(kind: .tiger, weight: 3, place: .surface, when: .any, biomes: [.jungle, .savanna], group: 1),
	SpawnRule(kind: .bear, weight: 3, place: .surface, when: .any, biomes: [.forest, .mountain], group: 1),
	SpawnRule(kind: .grizzly, weight: 2, place: .surface, when: .any, biomes: [.mountain, .forest], group: 1),
	SpawnRule(kind: .polarBear, weight: 4, place: .surface, when: .any, biomes: [.tundra], group: 1),
	SpawnRule(kind: .wolf, weight: 3, place: .surface, when: .night, biomes: [.tundra, .forest, .plains], group: 3),
	SpawnRule(kind: .frog, weight: 5, place: .surface, when: .any, biomes: [.swamp], group: 2),
	SpawnRule(kind: .scorpion, weight: 5, place: .surface, when: .any, biomes: [.desert], group: 1),
	// surface hostile
	SpawnRule(kind: .zombie, weight: 7, place: .surface, when: .night, biomes: [], group: 2),
	SpawnRule(kind: .slime, weight: 3, place: .surface, when: .night, biomes: [.plains, .forest, .jungle, .swamp], group: 1),
	// oceans
	SpawnRule(kind: .fish, weight: 8, place: .ocean, when: .any, biomes: [], group: 4),
	// caves
	SpawnRule(kind: .skeleton, weight: 6, place: .cave, when: .any, biomes: [], group: 2, minY: 150),
	SpawnRule(kind: .zombie, weight: 2, place: .cave, when: .any, biomes: [], group: 1, minY: 140),
	SpawnRule(kind: .slime, weight: 3, place: .cave, when: .any, biomes: [], group: 2, minY: 140),
	SpawnRule(kind: .bat, weight: 4, place: .cave, when: .any, biomes: [], group: 3, minY: 150),
	SpawnRule(kind: .wraith, weight: 2, place: .cave, when: .any, biomes: [], group: 1, minY: 380),
	SpawnRule(kind: .crawler, weight: 4, place: .cave, when: .any, biomes: [], group: 2, minY: 140),
	SpawnRule(kind: .archer, weight: 3, place: .cave, when: .any, biomes: [], group: 1, minY: 150),
	SpawnRule(kind: .golem, weight: 1.5, place: .cave, when: .any, biomes: [], group: 1, minY: 260),
	SpawnRule(kind: .archer, weight: 2, place: .surface, when: .night, biomes: [], group: 1),
	SpawnRule(kind: .skeleton, weight: 2, place: .surface, when: .night, biomes: [.plains, .desert, .tundra, .mountain, .savanna], group: 1),
	SpawnRule(kind: .crawler, weight: 2, place: .surface, when: .night, biomes: [.jungle, .swamp, .forest], group: 2),
	// umbral realm
	SpawnRule(kind: .imp, weight: 5, place: .umbral, when: .any, biomes: [], group: 1),
	SpawnRule(kind: .wraith, weight: 3, place: .umbral, when: .any, biomes: [], group: 1),
	SpawnRule(kind: .emberSlime, weight: 5, place: .umbral, when: .any, biomes: [], group: 2),
	SpawnRule(kind: .cinderBat, weight: 4, place: .umbral, when: .any, biomes: [], group: 3)
]

// MARK: - Mob instance

final class Mob {
	let id: Int
	var kind: MobKind
	var b: Body
	var hp: Double
	var maxHP: Double
	var dir: Int = 1
	var anim: Double = 0
	var hurtT: Double = 0
	var cd: Double = 0
	var t1: Double = 0
	var t2: Double = 0
	var t3: Double = 0
	var st: Int = 0
	var variant: Int = 0
	var tame: Bool = false
	var angry: Bool = false
	var persistent: Bool = false
	var sheared: Bool = false
	var blocking: Bool = false
	var boat: Int = -1
	var raiding: Bool = false
	var burn: Double = 0
	var stuckT: Double = 0
	var lastX: Double = 0
	var homeX: Double = 0
	var homeY: Double = 0
	var mounted: Bool = false
	var downed: Bool = false
	var lair: Int = 0
	var phase: Int = 0
	var tele: Double = 0
	var atk: Int = 0
	var tx: Double = 0
	var ty: Double = 0
	var regrow: Double = 0
	var knock: Double = 0
	/// time folded in while far-away AI updates were skipped
	var aiAccum: Double = 0
	/// set when the mob should leave the list at the end of the frame
	var removed: Bool = false
	/// white hit flash, death animation and knockback lean
	var flash: Double = 0
	var deathT: Double = -1
	var lean: Double = 0
	/// hazard and damage bookkeeping (see the damage system)
	var hazardT: Double = 0
	var lastAttacker: Int = 0
	var lastHitByPlayer: Double = -100
	var hitStamps: [Int: Double] = [:]
	var fallPeak: Double = 0
	var burnTick: Double = 0
	/// facing shown on screen, the turn animation and the attack lunge (visual only; the AI uses `dir`)
	var face: Int = 0
	var turnT: Double = 0
	var atkT: Double = 0
	/// a mimic's hoard (dropped when it dies) and the spots a telegraphed attack will strike
	var loot: [Stack] = []
	var spots: [Double] = []
	/// animal life: when to look around next, a place it is heading for (1 water, 2 its herd),
	/// a thirst timer, the prey it is hunting and a pose to hold (grazing, drinking)
	var thinkT: Double = 0
	/// boss attack variety: the last attack, how often in a row, and attacks since the signature move
	var lastAtk: Int = 0
	var repeatN: Int = 0
	var sinceSignature: Int = 0
	var goal: Int = 0
	var goalX: Double = 0
	var drinkT: Double = 0
	var preyID: Int = 0
	weak var prey: Mob? = nil
	var poseT: Double = 0
	/// dazed by a club: stands reeling, then can't be dazed again for a moment
	var daze: Double = 0
	var dazeGuard: Double = 0
	/// hostile AI (see `think`): its state and how long it has been in it, whether it can see the
	/// player (rechecked a few times a second), where it last saw them and how long ago, where it is
	/// heading, how long it has been pushing against a wall, and why it did not attack (for the overlay)
	var ai: MobAI = .idle
	var aiT: Double = 0
	var sees: Bool = false
	var losT: Double = 0
	var seenX: Double = 0
	var seenY: Double = 0
	var lostT: Double = 99
	var aimX: Double = 0
	var blockedT: Double = 0
	var progX: Double = 0
	var leapT: Double = 0
	var leapReq: Bool = false
	var why: AttackBlock = .none
	/// came out at night to look for the player; how long it has been far away and forgotten
	var hunter: Bool = false
	var farT: Double = 0
	/// a custom creature's slot in ModRuntime.mobs (-1 for the game's own creatures)
	var cslot: Int = -1
	/// custom creatures: each attack's cooldown, the creature it guards, the monster it fights or runs
	/// from (and timers for looking for them), its home biome, the blow under way (its key, target and
	/// whether that is the player) and how long a water creature has been on land
	var modCD: [Double] = []
	weak var ward: Mob? = nil
	var wardT: Double = 0
	weak var foe: Mob? = nil
	weak var threat: Mob? = nil
	var foeT: Double = 0
	var homeBiome: Int = -1
	var biomeT: Double = 0
	var strayed: Bool = false
	var atkKey: Int = 0
	var atkX: Double = 0
	var atkY: Double = 0
	var vsPlayer: Bool = true
	var dryT: Double = 0
	/// potion effects: slowed (by how much), poisoned (damage a second, and whether the player gets the
	/// credit), weakened, regenerating; and their timers
	var slowT: Double = 0
	var slowAmt: Double = 0
	var poisonT: Double = 0
	var poisonDps: Double = 0
	var poisonTick: Double = 0
	var poisonByPlayer: Bool = false
	var weakT: Double = 0
	var regenT: Double = 0
	var regenRate: Double = 0
	var regenAcc: Double = 0
	/// mutation: doses taken, the size its body has grown to and how much harder it hits
	var mut: Int = 0
	var mutSize: Double = 1
	var mutDmg: Double = 1
	/// custom creatures' fights (Mod Creator phases): the phase it is in (0: none yet) and its numbers
	/// there, how long it can't be hurt, how long it has been fighting, how many helpers it has called,
	/// the creature it helps (its id), whether a summoning called it, and how long the player has been gone
	var mphase: Int = 0
	var phaseSpeed: Double = 1
	var phaseDmg: Double = 1
	var phaseCD: Double = 1
	var phaseDef: Double = 0
	var phaseShield: Double = 0
	var fightT: Double = 0
	var helpersCalled: Int = 0
	var helperOf: Int = -1
	var summoned: Bool = false
	var leaveT: Double = 0
	static let turnDur: Double = 0.14
	static let atkDur: Double = 0.28

	init(id: Int, kind: MobKind, x: Double, y: Double) {
		self.id = id
		self.kind = kind
		let d: MobDef = mobDef(kind)
		self.b = Body(x: x, y: y, w: d.w, h: d.h)
		self.hp = d.hp
		self.maxHP = d.hp
		self.homeX = x
		self.homeY = y
		self.lastX = x
		self.dir = Int.random(in: 0...1) == 0 ? -1 : 1
		self.t1 = Double.random(in: 0.5...3.0)
	}

	var def: MobDef {
		if kind == .custom, let r = ModRuntime.shared.mob(cslot) { return r.mdef }
		return mobDef(kind)
	}
	var x: Double { return b.x }
	var y: Double { return b.y }
	/// a boss or guardian kind (worked out once: this is checked for every creature every frame)
	private(set) lazy var bossKind: Bool = Mob.isBossKind(kind, cslot)
	/// bosses never become tame, except the T-rex, which then stops being one
	var isBoss: Bool { return bossKind && !tame }

	static func isBossKind(_ k: MobKind, _ slot: Int) -> Bool {
		switch k {
		case .bearBoss, .rex, .sentinel, .warden: return true
		case .custom: return ModRuntime.shared.mob(slot)?.boss ?? false
		default: return false
		}
	}
}

/// What a hostile creature is doing. Attack and recover come from its attack routine (a wind-up, the
/// blow, the moment after); the rest are decided by `think`.
enum MobAI: UInt8 {
	case idle, alert, chase, search, back, retreat
	var name: String {
		switch self {
		case .idle: return "idle"
		case .alert: return "alert"
		case .chase: return "chase"
		case .search: return "search"
		case .back: return "return"
		case .retreat: return "regroup"
		}
	}
}

/// Why a creature that wants to hit the player has not (shown by the AI overlay)
enum AttackBlock: UInt8 {
	case none, notSeen, outOfRange, cooldown, noSight, tooHigh, blocked, peaceful, playerGone
	var name: String {
		switch self {
		case .none: return ""
		case .notSeen: return "hasn't seen you"
		case .outOfRange: return "out of range"
		case .cooldown: return "cooling down"
		case .noSight: return "no line of sight"
		case .tooHigh: return "can't reach that height"
		case .blocked: return "path blocked"
		case .peaceful: return "peaceful"
		case .playerGone: return "player dead"
		}
	}
}

struct MobSave: Codable {
	var kind: Int
	var x: Double
	var y: Double
	var hp: Double
	var maxHP: Double
	var tame: Bool
	var variant: Int
	var downed: Bool
	var lair: Int
	/// mutation doses (nil in saves from before mutation, and for creatures that never mutated)
	var mut: Int? = nil
}

// ===== p13b_vehicles =====

// MARK: - Vehicles (player built) and pirate ships

struct PartCell: Hashable, Codable {
	var dx: Int
	var dy: Int
}

struct VPartSave: Codable {
	var dx: Int
	var dy: Int
	var type: Int
	/// the block of a block cell (or the look of a mod block working as a part); nil for plain parts
	var tile: Int? = nil
	/// damage the cell has taken (nil: none)
	var dmg: Double? = nil
	/// a wing's tilt (nil: none)
	var tilt: Int? = nil
	/// a cell of a part bigger than one cell: the part's middle cell (dx, dy)
	var span: [Int]? = nil
}

/// A point on an autopilot's route (world coordinates)
struct VWaypoint: Codable {
	var x: Double
	var y: Double
}

struct VehicleSave: Codable {
	var id: Int
	var parts: [VPartSave]
	/// centre of mass (saves with `rot`), or the bottom-centre of the box (older saves)
	var x: Double
	var y: Double
	var fuel: Double
	var dir: Int
	var kit: Int?
	/// rotation in radians; nil in saves made before vehicles could rotate
	var rot: Double? = nil
	/// the autopilot's mode and route (nil: off, none)
	var auto: Int? = nil
	var route: [VWaypoint]? = nil
	/// the driver's seat (dx, dy) and the back walls (dx, dy, wall), when there are any
	var seat: [Int]? = nil
	var walls: [[Int]]? = nil
	/// how full the ballast tanks are (nil: empty)
	var ballast: Double? = nil
	/// its couplings to other vehicles (a train)
	var links: [VLink]? = nil
	/// its joints, the section it hangs from, and its walk
	var joints: [VJoint]? = nil
	var parent: Int? = nil
	var gait: Double? = nil
	/// how its guns fire (dx, dy, mode)
	var gunModes: [[Int]]? = nil
	/// its receivers' channel, and what they do while it is on
	var channel: Int? = nil
	var radioAct: Int? = nil
}

/// Displaced volume per part (how much it floats)
func partVolume(_ p: PartType) -> Double {
	switch p {
	case .hull: return 4.0
	case .frame: return 0.3
	case .fuelTank: return 0.25
	case .seat: return 0.1
	default: return 0.0
	}
}

/// Mining power of a drill part: (tier it can break, speed)
func drillPower(_ p: PartType) -> (Int, Double) {
	switch p {
	case .drill: return (4, 4.6)
	case .diamondDrill: return (7, 8.5)
	case .voidDrill: return (9, 13.0)
	default: return (0, 0)
	}
}

func isDrill(_ p: PartType) -> Bool { return p == .drill || p == .diamondDrill || p == .voidDrill }

/// Parts that point somewhere (their open side): thrusters, the tail rotor and the guns
func isFacingPart(_ p: PartType) -> Bool {
	return p == .airProp || p == .jet || p == .tailRotor || p == .cannon || p == .autoGun
}

/// One cell taken off a vehicle: what it was, and its block if it was one
struct VCell {
	var cell: PartCell
	var type: PartType
	var tile: Tile?
}

/// A player-built vehicle: a rigid body made of 1x1 parts. It has a centre of mass, a rotation and
/// an angular velocity, and every part collides, floats and drives at its rotated position, so
/// what you see is exactly what touches the world.
final class Vehicle {
	let id: Int
	var parts: [PartCell: PartType] = [:]
	/// world-space bounding box of the rotated parts (kept for spawning, decks, pick tests)
	var b: Body
	// rigid body state
	var px: Double = 0
	var py: Double = 0
	var vx: Double = 0
	var vy: Double = 0
	var angle: Double = 0
	var angVel: Double = 0
	/// centre of mass in cell coordinates (cell (0,0) spans 0...1)
	var comX: Double = 0.5
	var comY: Double = 0.5
	var inertia: Double = 1
	var fuel: Double = 0
	var dir: Int = 1
	var minX: Int = 0
	var maxX: Int = 0
	var minY: Int = 0
	var maxY: Int = 0
	var mass: Double = 1
	var buoyancy: Double = 0
	var engines: Int = 0
	var wheels: Int = 0
	var propellers: Int = 0
	var paddles: Int = 0
	var tanks: Int = 0
	var drills: Int = 0
	var offroadWheels: Int = 0
	var headlights: Int = 0
	var hasSeat: Bool = false
	var hasSteering: Bool = false
	var throttle: Double = 0
	var wheelRot: Double = 0
	var rider: Bool = false
	var propRot: Double = 0
	var drillRot: Double = 0
	var drilling: Bool = false
	var smoke: Double = 0
	/// contacts touched in the last physics step (wheels on the ground, any part on the ground)
	var wheelContacts: Int = 0
	var contacts: Int = 0
	var submerged: Double = 0
	var sleepT: Double = 0
	var asleep: Bool = false
	/// physics time not yet simulated (vehicles step at a fixed rate)
	var physAccum: Double = 0
	/// direction each drill faces in vehicle space, and its mining progress
	var drillDir: [PartCell: (Int, Int)] = [:]
	var drillWork: [PartCell: (Int, Int, Double)] = [:]
	/// the kit this vehicle came from (-1 = built part by part, or changed since)
	var kit: Int = -1
	/// the block in each block cell (and the look of a mod block that works as a part)
	var blocks: [PartCell: Tile] = [:]
	/// damage each cell has taken (see vehicleCellHP); a cell that takes its fill breaks off
	var dmg: [PartCell: Double] = [:]
	/// which way each thruster, gun and tail rotor points in vehicle space (its open side)
	var face: [PartCell: (Int, Int)] = [:]
	// parts of aircraft, airships, tanks and armed vehicles
	var wings: Int = 0
	var elevators: Int = 0
	var airProps: Int = 0
	var jets: Int = 0
	var rotors: Int = 0
	var tailRotors: Int = 0
	var envelopes: Int = 0
	var burners: Int = 0
	var tracks: Int = 0
	var armors: Int = 0
	var cannons: Int = 0
	var guns: Int = 0
	var autopilots: Int = 0
	var receivers: Int = 0
	var hasCockpit: Bool = false
	/// something that works in the air (wings, thrusters, rotors, balloons): the flight model runs
	var aero: Bool = false
	/// the pilot's up/down input (-1...1, up is positive): elevators, rotor pitch, burner heat
	var pitch: Double = 0
	/// main rotor blade pitch (0...1) and the air heat in the balloon (0...1)
	var collective: Double = 0
	var heat: Double = 0
	/// the end the nose is at, along the vehicle's own x axis (1 or -1)
	var fwd: Int = 1
	/// for the instruments: last step's lift and thrust, and whether a wing has stalled
	var liftNow: Double = 0
	var thrustNow: Double = 0
	var stall: Bool = false
	var airspeed: Double = 0
	/// the steepest angle the air meets a wing at (radians)
	var alpha: Double = 0
	/// a turn to face the other way in progress (0...1; 0 = none) and the speed it started from
	var turnT: Double = 0
	var turnVX: Double = 0
	var turned: Bool = false
	/// each gun's reload and the way its barrel points (world angle)
	var gunCD: [PartCell: Double] = [:]
	var aimAng: [PartCell: Double] = [:]
	/// autopilot: 0 off, 1 cruise, 2 route; what cruise holds; the marked route and the next point
	var auto: Int = 0
	var holdThr: Double = 0
	var holdY: Double = 0
	var holdVX: Double = 0
	var route: [VWaypoint] = []
	var routeAt: Int = 0
	/// time the rotor blades have been striking the ground (they break)
	var bladeHit: Double = 0
	/// the elevator trim the flight model finds by itself (so a plane holds its attitude hands-off), and
	/// the cyclic's (so a helicopter holds its tilt)
	var trim: Double = 0
	var cycI: Double = 0
	/// the wind at the vehicle this frame (blocks per second, signed)
	var windX: Double = 0
	/// flashes red for a moment when hit
	var hitT: Double = 0
	/// how strong each mod block working as a part is at its work (1: the game part's own)
	var boost: [PartCell: Double] = [:]
	/// the engines' power (a mod engine can be stronger or weaker than the game's)
	var enginePower: Double = 0
	/// what each cell is to somebody walking on the vehicle (see Vehicle.walkKind), over the cells' box
	var walkGrid: [UInt8] = []
	var gridW: Int = 0
	var gridH: Int = 0
	/// how far its furthest corner is from its centre of mass (blocks)
	var radius: Double = 1
	/// what each cell is to another vehicle meeting it (solid, stood on from above, or nothing)
	var meetGrid: [UInt8] = []
	/// being stepped in this frame's physics (it moves when pushed); the vehicle it rests on (0: none)
	var inStep: Bool = false
	var restOn: Int = 0
	/// what other vehicles met of it in this frame (their samples in its cells), and one that it rests
	/// on that found it so
	var touched: Int = 0
	var leanOn: Int = 0
	/// the seat the driver sat down in (with several seats)
	var seatAt: PartCell? = nil
	/// back walls behind cells, inside the vehicle's box (the same numbers as the land's walls)
	var walls: [PartCell: UInt8] = [:]
	/// counts every change to how it looks (its cached picture is redrawn when this moves on), and that
	/// picture (see VehicleArt)
	var artRev: Int = 0
	var artImage: Image? = nil
	var artKey: Int = -1
	/// thrusters, guns and drills with no open side to work from (they wait for one)
	var boxed: Set<PartCell> = []
	/// how much room each rotor's blades have (1: all of it; parts in the row above take some), and
	/// the rotors' lift in all (in rotors)
	var rotorRoom: [PartCell: Double] = [:]
	var rotorLift: Double = 0
	/// the propellers, paddles and tail rotors that are free to push
	var openProps: Int = 0
	var openPaddles: Int = 0
	var openTails: Int = 0
	/// flight and water: each wing's tilt (steps of Aero.tiltStep; saved), flaps, air brakes, tailplanes
	/// and ballast tanks, how full the ballast tanks are (0 air ... 1 water), and how far the air brakes
	/// are open
	var tilt: [PartCell: Int] = [:]
	var flaps: Int = 0
	var airBrakes: Int = 0
	var stabilizers: Int = 0
	var ballasts: Int = 0
	var ballast: Double = 0
	var brakeOpen: Double = 0
	/// the cells inside it that are under the surface of what it floats in, and how flooded each is
	/// (0 dry air ... 1 full); worked out a few times a second (see updateHullAir)
	var hullAir: [PartCell: Double] = [:]
	var hullT: Double = 0
	/// parts bigger than one cell: every cell of one, mapped to its middle cell (where it is counted,
	/// weighs and is drawn); the couplers, and the links to other vehicles they make (a train)
	var spanOf: [PartCell: PartCell] = [:]
	var couplers: Int = 0
	var railWheels: Int = 0
	var links: [VLink] = []
	/// a moment after being uncoupled by hand, before its couplers link again
	var noCoupleT: Double = 0
	/// its joints to the sections built on beyond them, the section it hangs from (0: none), and how far
	/// round its walk is (a mech)
	var joints: [VJoint] = []
	var parentID: Int = 0
	var gait: Double = 0
	/// a machine section's places on the land from its last step, worked out again with its joints
	/// (not saved)
	var heldContacts: [VContact] = []
	/// how each gun fires (GunMode's number; none: with the driver's attack)
	var gunMode: [PartCell: Int] = [:]
	/// the signal channel its receivers pick up (1 to 8; 0: none) and what it does while that channel is
	/// on (RadioAct's number)
	var channel: Int = 0
	var radioAct: Int = 0
	/// its channel is on now, and that signal is driving it (not saved)
	var signalOn: Bool = false
	var signalDrive: Bool = false
	/// how far into its stride a mech's legs swing (rises as it walks, falls back as it stops) and the
	/// way it last walked (not saved)
	var gaitAmp: Double = 0
	var gaitDir: Double = 1
	/// its collision samples, kept until it changes
	var sampleCache: [VSample] = []
	var sampleKey: Int = -1

	init(id: Int, first: PartType, x: Double, y: Double) {
		self.id = id
		self.b = Body(x: x, y: y, w: 1, h: 1)
		parts[PartCell(dx: 0, dy: 0)] = first
		recompute(keepAnchor: false)
		placeBox(left: x - 0.5, bottom: y)
	}

	// MARK: transforms

	var cosA: Double { return cos(angle) }
	var sinA: Double { return sin(angle) }

	/// vehicle-space point (cell units) to world
	func toWorld(_ lx: Double, _ ly: Double) -> (Double, Double) {
		let ox: Double = lx - comX
		let oy: Double = ly - comY
		let c: Double = cosA
		let s: Double = sinA
		return (px + ox * c - oy * s, py + ox * s + oy * c)
	}

	/// world point to vehicle space (cell units)
	func toLocal(_ wx: Double, _ wy: Double) -> (Double, Double) {
		let dx: Double = wx - px
		let dy: Double = wy - py
		let c: Double = cosA
		let s: Double = sinA
		return (dx * c + dy * s + comX, -dx * s + dy * c + comY)
	}

	func cellCenter(_ c: PartCell) -> (Double, Double) {
		return toWorld(Double(c.dx) + 0.5, Double(c.dy) + 0.5)
	}

	/// top-left of the cell's (unrotated) box around its rotated centre
	func cellPos(_ c: PartCell) -> (Double, Double) {
		let p: (Double, Double) = cellCenter(c)
		return (p.0 - 0.5, p.1 - 0.5)
	}

	func cellAt(_ wx: Double, _ wy: Double) -> PartCell {
		let l: (Double, Double) = toLocal(wx, wy)
		return PartCell(dx: Int(floor(l.0)), dy: Int(floor(l.1)))
	}

	/// Places an unrotated vehicle so its parts' box has this left edge and bottom
	func placeBox(left: Double, bottom: Double) {
		angle = 0
		px = left + (comX - Double(minX))
		py = bottom - (Double(maxY + 1) - comY)
		updateBox()
	}

	/// Recomputes the world bounding box from the rotated part corners
	func updateBox() {
		var x0: Double = 1e9, x1: Double = -1e9, y0: Double = 1e9, y1: Double = -1e9
		let c: Double = cosA
		let s: Double = sinA
		for (cell, _) in parts {
			let corners: [(Double, Double)] = [(0, 0), (1, 0), (0, 1), (1, 1)]
			for k in corners {
				let ox: Double = Double(cell.dx) + k.0 - comX
				let oy: Double = Double(cell.dy) + k.1 - comY
				let wx: Double = px + ox * c - oy * s
				let wy: Double = py + ox * s + oy * c
				x0 = min(x0, wx); x1 = max(x1, wx); y0 = min(y0, wy); y1 = max(y1, wy)
			}
		}
		b.w = max(0.1, x1 - x0)
		b.h = max(0.1, y1 - y0)
		b.x = (x0 + x1) * 0.5
		b.y = y1
		b.vx = vx
		b.vy = vy
	}

	func recompute(keepAnchor: Bool) {
		// remember where one surviving cell is, so the rest of the vehicle stays put in the world
		var anchor: PartCell? = nil
		var anchorW: (Double, Double) = (0, 0)
		if keepAnchor, let c0 = parts.keys.first {
			anchor = c0
			anchorW = cellCenter(c0)
		}
		var x0: Int = 0, x1: Int = 0, y0: Int = 0, y1: Int = 0
		var first: Bool = true
		mass = 0
		buoyancy = 0
		engines = 0; wheels = 0; propellers = 0; paddles = 0; tanks = 0; drills = 0; offroadWheels = 0; headlights = 0
		wings = 0; elevators = 0; airProps = 0; jets = 0; rotors = 0; tailRotors = 0; envelopes = 0; burners = 0
		tracks = 0; armors = 0; cannons = 0; guns = 0; autopilots = 0; receivers = 0
		flaps = 0; airBrakes = 0; stabilizers = 0; ballasts = 0; couplers = 0; railWheels = 0
		spanOf = spanOf.filter { parts[$0.key] != nil }
		hasSeat = false
		hasSteering = false
		hasCockpit = false
		blocks = blocks.filter { parts[$0.key] != nil }
		dmg = dmg.filter { parts[$0.key] != nil }
		var mx: Double = 0
		var my: Double = 0
		for (c, t) in parts {
			if first { x0 = c.dx; x1 = c.dx; y0 = c.dy; y1 = c.dy; first = false }
			x0 = min(x0, c.dx); x1 = max(x1, c.dx); y0 = min(y0, c.dy); y1 = max(y1, c.dy)
			// (the outer cells of a big part are counted and weighed at its middle)
			if let k = spanOf[c], k != c { continue }
			let pm: Double = cellMass(c, t)
			mass += pm
			mx += pm * (Double(c.dx) + 0.5)
			my += pm * (Double(c.dy) + 0.5)
			buoyancy += partVolume(t)
			countPart(t)
		}
		aero = wings + elevators + airProps + jets + rotors + envelopes + airBrakes + stabilizers > 0
		tilt = tilt.filter { parts[$0.key] != nil }
		joints = joints.filter { parts[$0.cell] != nil }
		hullAir = hullAir.filter { parts[$0.key] == nil || Vehicle.walkKind(parts[$0.key]!, blocks[$0.key]) != cellSolid }
		// back walls weigh a little where they are
		for (c, k) in walls {
			let wm: Double = vehicleWallMass(k)
			mass += wm
			mx += wm * (Double(c.dx) + 0.5)
			my += wm * (Double(c.dy) + 0.5)
		}
		minX = x0; maxX = x1; minY = y0; maxY = y1
		mass = max(0.3, mass)
		comX = mx / mass
		comY = my / mass
		// moment of inertia: each part as a 1x1 plate around the centre of mass
		var inert: Double = 0
		for (c, t) in parts {
			let ox: Double = Double(c.dx) + 0.5 - comX
			let oy: Double = Double(c.dy) + 0.5 - comY
			inert += cellMass(c, t) * (ox * ox + oy * oy + 1.0 / 6.0)
		}
		inertia = max(0.2, inert)
		var far: Double = 0.5
		for (c, _) in parts {
			let ox: Double = abs(Double(c.dx) + 0.5 - comX) + 0.5
			let oy: Double = abs(Double(c.dy) + 0.5 - comY) + 0.5
			far = max(far, sqrt(ox * ox + oy * oy))
		}
		radius = far
		findFacings()
		findBoxedParts()
		boost.removeAll()
		for (c, b) in blocks where b.isMod && parts[c] != .block {
			if let d = ModRuntime.shared.blockDef(b) { boost[c] = d.vehPower }
		}
		enginePower = 0
		for (c, t) in parts where t == .engine { enginePower += boost[c] ?? 1.0 }
		// drills face the open side of their cell
		drillDir.removeAll()
		for (c, t) in parts where isDrill(t) {
			let free: (PartCell) -> Bool = { self.parts[$0] == nil }
			if free(PartCell(dx: c.dx + 1, dy: c.dy)) && !free(PartCell(dx: c.dx - 1, dy: c.dy)) { drillDir[c] = (1, 0) }
			else if free(PartCell(dx: c.dx - 1, dy: c.dy)) && !free(PartCell(dx: c.dx + 1, dy: c.dy)) { drillDir[c] = (-1, 0) }
			else if free(PartCell(dx: c.dx, dy: c.dy + 1)) { drillDir[c] = (0, 1) }
			else if free(PartCell(dx: c.dx + 1, dy: c.dy)) { drillDir[c] = (1, 0) }
			else { drillDir[c] = (0, -1) }
		}
		drillWork = drillWork.filter { parts[$0.key] != nil }
		buildWalkGrid()
		if let a = anchor, parts[a] != nil {
			// put the anchor cell back where it was
			let ox: Double = Double(a.dx) + 0.5 - comX
			let oy: Double = Double(a.dy) + 0.5 - comY
			let c: Double = cosA
			let s: Double = sinA
			px = anchorW.0 - (ox * c - oy * s)
			py = anchorW.1 - (ox * s + oy * c)
		}
		asleep = false
		updateBox()
	}

	/// How much one cell weighs: a part's own mass, or the weight of the block it is (stone 2.5)
	func cellMass(_ c: PartCell, _ t: PartType) -> Double {
		if let b = blocks[c] { return vehicleBlockMass(b, t) }
		return t.mass
	}

	func countPart(_ t: PartType) {
		switch t {
		case .engine: engines += 1
		case .wheel: wheels += 1
		case .offroadWheel: wheels += 1; offroadWheels += 1
		case .track: wheels += 1; tracks += 1
		case .headlight: headlights += 1
		case .propeller: propellers += 1
		case .paddle: paddles += 1
		case .fuelTank: tanks += 1
		case .seat: hasSeat = true
		case .steering: hasSteering = true
		case .cockpit: hasSeat = true; hasSteering = true; hasCockpit = true
		case .drill, .diamondDrill, .voidDrill: drills += 1
		case .wing: wings += 1
		case .elevator: elevators += 1
		case .airProp: airProps += 1
		case .jet: jets += 1
		case .rotor: rotors += 1
		case .tailRotor: tailRotors += 1
		case .envelope: envelopes += 1
		case .burner: burners += 1
		case .armor: armors += 1
		case .cannon: cannons += 1
		case .autoGun: guns += 1
		case .autopilot: autopilots += 1
		case .receiver: receivers += 1
		case .flap: wings += 1; flaps += 1
		case .airBrake: airBrakes += 1
		case .stabilizer: stabilizers += 1
		case .ballast: ballasts += 1
		case .railWheel: wheels += 1; railWheels += 1
		case .bigWheel: wheels += 1; offroadWheels += 1
		case .coupler: couplers += 1
		default: break
		}
	}

	/// Thrusters, guns and tail rotors point out of their open side: left or right for thrusters and
	/// tail rotors (the side away from the centre when both are open), any side for guns (up first
	/// when the top is open, so a turret on a roof looks up and round)
	func findFacings() {
		face.removeAll()
		for (c, t) in parts where isFacingPart(t) {
			let r: Bool = parts[PartCell(dx: c.dx + 1, dy: c.dy)] == nil
			let l: Bool = parts[PartCell(dx: c.dx - 1, dy: c.dy)] == nil
			let u: Bool = parts[PartCell(dx: c.dx, dy: c.dy - 1)] == nil
			let d: Bool = parts[PartCell(dx: c.dx, dy: c.dy + 1)] == nil
			let away: Int = Double(c.dx) + 0.5 >= comX ? 1 : -1
			var f: (Int, Int) = (away, 0)
			if r && l { f = (away, 0) } else if r { f = (1, 0) } else if l { f = (-1, 0) }
			else if t == .cannon || t == .autoGun { f = u ? (0, -1) : (d ? (0, 1) : (away, 0)) }
			if (t == .cannon || t == .autoGun) && u && !(r || l) { f = (0, -1) }
			face[c] = f
		}
	}

	/// Parts that need room to work: a thruster needs one end open (left or right), a gun any side, a
	/// drill a side or its underside; a rotor lifts by how much of its blades' row (two cells either side
	/// above it) is clear
	func findBoxedParts() {
		boxed.removeAll()
		rotorRoom.removeAll()
		rotorLift = 0
		openProps = 0
		openPaddles = 0
		openTails = 0
		for (c, t) in parts {
			let r: Bool = parts[PartCell(dx: c.dx + 1, dy: c.dy)] == nil
			let l: Bool = parts[PartCell(dx: c.dx - 1, dy: c.dy)] == nil
			let u: Bool = parts[PartCell(dx: c.dx, dy: c.dy - 1)] == nil
			let d: Bool = parts[PartCell(dx: c.dx, dy: c.dy + 1)] == nil
			switch t {
			case .propeller, .paddle, .airProp, .jet, .tailRotor:
				if !(r || l) { boxed.insert(c); continue }
				if t == .propeller { openProps += 1 }
				if t == .paddle { openPaddles += 1 }
				if t == .tailRotor { openTails += 1 }
			case .cannon, .autoGun:
				if !(r || l || u || d) { boxed.insert(c) }
			case .drill, .diamondDrill, .voidDrill:
				if !(r || l || d || u) { boxed.insert(c) }
			case .rotor:
				var free: Int = 0
				for k in -2...2 where parts[PartCell(dx: c.dx + k, dy: c.dy - 1)] == nil { free += 1 }
				let room: Double = Double(free) / 5.0
				rotorRoom[c] = room
				rotorLift += room
			default:
				break
			}
		}
	}

	var fuelCapacity: Double { return Double(tanks) * 60.0 + (engines > 0 || jets > 0 || burners > 0 ? 8.0 : 0.0) }
	var isBoat: Bool { return buoyancy > 0 }
	var canDriveOnLand: Bool { return wheels >= 2 && engines > 0 }
	var canSail: Bool { return buoyancy >= mass * 0.8 && ((engines > 0 && propellers > 0) || paddles > 0) }
	var topY: Double { return b.y - b.h }
	var speed: Double { return sqrt(vx * vx + vy * vy) }
	/// roughly upright (flat enough to stand on, to place kits next to, and so on)
	var upright: Bool { return abs(remainder(angle, 2.0 * Double.pi)) < 0.35 }

	func hasNeighbor(_ c: PartCell) -> Bool {
		let n: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy), PartCell(dx: c.dx, dy: c.dy + 1), PartCell(dx: c.dx, dy: c.dy - 1)]
		for k in n { if parts[k] != nil { return true } }
		return false
	}

	func canAttach(_ c: PartCell, _ t: PartType) -> Bool {
		if parts[c] != nil { return false }
		if !hasNeighbor(c) { return false }
		if isWheelPart(t) {
			// wheels hang below the body: something must be directly above, nothing below
			if parts[PartCell(dx: c.dx, dy: c.dy - 1)] == nil { return false }
			if parts[PartCell(dx: c.dx, dy: c.dy + 1)] != nil { return false }
		}
		if t == .steering {
			let n: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy), PartCell(dx: c.dx, dy: c.dy + 1), PartCell(dx: c.dx, dy: c.dy - 1)]
			var ok: Bool = false
			for k in n { if parts[k] == .seat { ok = true } }
			if !ok { return false }
		}
		if t == .propeller || t == .paddle || t == .airProp || t == .jet || t == .tailRotor {
			// must sit at the edge of the vehicle
			let side: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy)]
			var free: Bool = false
			for k in side { if parts[k] == nil { free = true } }
			if !free { return false }
		}
		if t == .rotor {
			// on top, with room for the blades: nothing in the row above, two cells either side
			for k in -2...2 where parts[PartCell(dx: c.dx + k, dy: c.dy - 1)] != nil { return false }
		}
		// nothing goes where a rotor's blades turn
		for k in -2...2 where parts[PartCell(dx: c.dx + k, dy: c.dy + 1)] == .rotor { return false }
		if t == .cannon || t == .autoGun {
			// a gun needs one open side to fire from
			let n: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy), PartCell(dx: c.dx, dy: c.dy - 1), PartCell(dx: c.dx, dy: c.dy + 1)]
			var free: Bool = false
			for k in n { if parts[k] == nil { free = true } }
			if !free { return false }
		}
		if isDrill(t) {
			// a drill needs one open side to bore into
			let n: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy), PartCell(dx: c.dx, dy: c.dy + 1)]
			var free: Bool = false
			for k in n { if parts[k] == nil { free = true } }
			if !free { return false }
		}
		return true
	}

	/// Removes a part, returning every part that is no longer connected (including the removed one)
	func removePart(_ c: PartCell) -> [PartType] {
		return cutAway(c).map { $0.type }
	}

	/// The groups of cells that hang together (side by side), largest first
	func connectedGroups() -> [[PartCell]] {
		var seen: Set<PartCell> = []
		var out: [[PartCell]] = []
		for start in parts.keys where !seen.contains(start) {
			var group: [PartCell] = []
			var stack: [PartCell] = [start]
			while let cur = stack.popLast() {
				if seen.contains(cur) { continue }
				seen.insert(cur)
				group.append(cur)
				let n: [PartCell] = [PartCell(dx: cur.dx + 1, dy: cur.dy), PartCell(dx: cur.dx - 1, dy: cur.dy), PartCell(dx: cur.dx, dy: cur.dy + 1), PartCell(dx: cur.dx, dy: cur.dy - 1)]
				for k in n where parts[k] != nil && !seen.contains(k) { stack.append(k) }
			}
			out.append(group)
		}
		out.sort { $0.count > $1.count }
		return out
	}

	/// Removes a cell and everything no longer joined to the part that stays (the group holding `keep`
	/// if it survives, otherwise the largest), returning what came off (the removed cell first)
	func cutAway(_ c: PartCell, keep: PartCell? = nil) -> [VCell] {
		var out: [VCell] = []
		if let mid = spanOf[c] {
			// a part bigger than one cell comes away whole (given back once, from its middle)
			for (k, m) in spanOf where m == mid {
				if k == mid, let t = parts[k] { out.append(VCell(cell: k, type: t, tile: blocks[k])) }
				parts[k] = nil
				blocks[k] = nil
				dmg[k] = nil
				spanOf[k] = nil
			}
			if parts.isEmpty { return out }
		}
		if let t = parts[c] { out.append(VCell(cell: c, type: t, tile: blocks[c])) }
		parts[c] = nil
		blocks[c] = nil
		dmg[c] = nil
		if parts.isEmpty { return out }
		let groups: [[PartCell]] = connectedGroups()
		var stay: [PartCell] = groups[0]
		if let k = keep, parts[k] != nil {
			for g in groups where g.contains(k) { stay = g }
		}
		let staySet: Set<PartCell> = Set(stay)
		for k in Array(parts.keys) where !staySet.contains(k) {
			let outer: Bool = spanOf[k] != nil && spanOf[k] != k
			if let t = parts[k], !outer { out.append(VCell(cell: k, type: t, tile: blocks[k])) }
			parts[k] = nil
			blocks[k] = nil
			dmg[k] = nil
			spanOf[k] = nil
		}
		return out
	}

	func save() -> VehicleSave {
		var ps: [VPartSave] = []
		for (c, t) in parts {
			var e = VPartSave(dx: c.dx, dy: c.dy, type: t.rawValue)
			if let b = blocks[c] { e.tile = Int(b.rawValue) }
			if let d = dmg[c], d > 0 { e.dmg = d }
			if let k = tilt[c], k != 0 { e.tilt = k }
			if let m = spanOf[c] { e.span = [m.dx, m.dy] }
			ps.append(e)
		}
		var s = VehicleSave(id: id, parts: ps, x: px, y: py, fuel: fuel, dir: dir, kit: kit, rot: angle)
		if auto != 0 { s.auto = auto }
		if !route.isEmpty { s.route = route }
		if let c = seatAt { s.seat = [c.dx, c.dy] }
		if ballast > 0.001 { s.ballast = ballast }
		if !links.isEmpty { s.links = links }
		if !joints.isEmpty { s.joints = joints }
		if parentID != 0 { s.parent = parentID }
		if gait != 0 { s.gait = gait }
		if !gunMode.isEmpty { s.gunModes = gunMode.map { [$0.key.dx, $0.key.dy, $0.value] } }
		if channel != 0 { s.channel = channel }
		if radioAct != 0 { s.radioAct = radioAct }
		if !walls.isEmpty { s.walls = walls.map { [$0.key.dx, $0.key.dy, Int($0.value)] } }
		return s
	}

	static func restore(_ s: VehicleSave) -> Vehicle {
		let v = Vehicle(id: s.id, first: .frame, x: s.x, y: s.y)
		v.parts.removeAll()
		for p in s.parts {
			let c: PartCell = PartCell(dx: p.dx, dy: p.dy)
			let t: PartType = PartType(rawValue: p.type) ?? .frame
			v.parts[c] = t
			if let tr = p.tile, tr >= 0, tr < 256, let b = Tile(rawValue: UInt8(tr)) { v.blocks[c] = b }
			else if t == .block { v.blocks[c] = .planks }
			if let d = p.dmg { v.dmg[c] = d }
			if let k = p.tilt, k != 0 { v.tilt[c] = clampI(k, -Aero.tiltSteps, Aero.tiltSteps) }
			if let m = p.span, m.count == 2 { v.spanOf[c] = PartCell(dx: m[0], dy: m[1]) }
		}
		if v.parts.isEmpty { v.parts[PartCell(dx: 0, dy: 0)] = .frame }
		v.auto = s.auto ?? 0
		v.route = s.route ?? []
		if let c = s.seat, c.count == 2 { v.seatAt = PartCell(dx: c[0], dy: c[1]) }
		v.ballast = clampD(s.ballast ?? 0, 0, 1)
		v.links = s.links ?? []
		v.parentID = s.parent ?? 0
		v.gait = s.gait ?? 0
		for w in s.walls ?? [] where w.count == 3 && w[2] > 0 && w[2] < 256 { v.walls[PartCell(dx: w[0], dy: w[1])] = UInt8(w[2]) }
		v.recompute(keepAnchor: false)
		if let r = s.rot {
			v.px = s.x
			v.py = s.y
			v.angle = r
			v.updateBox()
		} else {
			// older save: x, y were the bottom-centre of an unrotated box
			let w: Double = Double(v.maxX - v.minX + 1)
			v.placeBox(left: s.x - w * 0.5, bottom: s.y)
		}
		v.fuel = s.fuel
		v.dir = s.dir
		v.kit = s.kit ?? -1
		v.joints = (s.joints ?? []).filter { v.parts[$0.cell] != nil }
		for g in s.gunModes ?? [] where g.count == 3 && g[2] > 0 {
			let c: PartCell = PartCell(dx: g[0], dy: g[1])
			if v.parts[c] != nil { v.gunMode[c] = clampI(g[2], 0, GunMode.allCases.count - 1) }
		}
		v.channel = clampI(s.channel ?? 0, 0, Radio.channels)
		v.radioAct = clampI(s.radioAct ?? 0, 0, RadioAct.allCases.count - 1)
		return v
	}
}

// MARK: - Pirate ships

final class PirateShip {
	let id: Int
	var x: Double
	var dir: Int
	var hp: Double = 180
	var maxHP: Double = 180
	var crew: [Int] = []
	var state: Int = 0
	var t: Double = 0
	var looted: Bool = false
	var bob: Double = 0
	var patrolMin: Double
	var patrolMax: Double
	var sink: Double = 0
	var hitT: Double = 0
	var speed: Double = 0

	static let deckHalf: Double = 4.0
	static let spriteW: Double = 9.5
	static let spriteH: Double = 5.0
	static let waterRow: Double = 3.6
	static let deckRow: Double = 2.625

	init(id: Int, x: Double, dir: Int, pMin: Double, pMax: Double) {
		self.id = id
		self.x = x
		self.dir = dir
		self.patrolMin = pMin
		self.patrolMax = pMax
	}

	/// y of the deck standing line in tiles
	func deckY(_ seaY: Double) -> Double {
		return seaY - PirateShip.waterRow + PirateShip.deckRow + sink + sin(bob) * 0.12
	}
}

// ===== p14a_game =====

// MARK: - Game state

enum GameMode: String, Codable {
	case survival, creative, hardcore
	var title: String { return rawValue.capitalized }
}

struct Settings: Codable {
	/// the player's look (the character screen): hair colour and style, shirt colour and style, trouser
	/// colour and style, scarf (each a place in its list: hairChoices, hairStyleNames, ...)
	var hair: Int = 0
	var scarf: Int = 0
	var hairStyle: Int = 0
	var shirtColor: Int = 0
	var shirtStyle: Int = 0
	var pantsColor: Int = 0
	var pantsStyle: Int = 0
	var touchControls: Bool = true
	var peaceful: Bool = false
	var showCoords: Bool = true
	var tilePx: Int = 24
	var rareChance: Double = 0.28
	var smoothLight: Bool = true
	/// true = 60 frames per second, false = 30 (smoother on older iPads)
	var fps60: Bool = true
	var showFPS: Bool = false
	// camera
	var camSmoothOn: Bool = true
	/// 0 = loose and floaty, 1 = tight
	var camFollow: Double = 0.55
	/// tiles the player can move before the camera starts to follow
	var camDeadZone: Double = 0.8
	var camLookAhead: Bool = true
	/// the camera stays on the player: no dead zone, no look-ahead, a quick smooth follow
	var camDirect: Bool = false
	var shakeOn: Bool = true
	var shakeIntensity: Double = 0.5
	var showTrajectory: Bool = true
	// sound
	var soundOn: Bool = true
	var sfxVolume: Double = 0.7
	var ambienceVolume: Double = 0.5
	// weather: a master switch, a switch for each kind, what it may damage, how strong and how often
	// severe weather is, alerts, how much is drawn, and gentler lightning
	var weatherOn: Bool = true
	var allowRain: Bool = true
	var allowThunder: Bool = true
	var allowWind: Bool = true
	var allowTornado: Bool = true
	var allowHurricane: Bool = true
	var allowBlizzard: Bool = true
	var allowHail: Bool = true
	var weatherHurtsPlayer: Bool = true
	var weatherHurtsBlocks: Bool = true
	var weatherHurtsCreatures: Bool = true
	/// 0.25 (gentle) ... 1.5 (fierce)
	var weatherIntensity: Double = 1.0
	/// how often severe weather comes: 0 rare, 1 normal, 2 frequent
	var severeFrequency: Int = 1
	var weatherAlerts: Bool = true
	/// 0.2 ... 1: how many raindrops, flakes and stones are drawn
	var weatherParticles: Double = 1.0
	/// lightning lights the scene gently instead of flashing it (strikes still happen)
	var reduceFlashes: Bool = false
	/// how dangerous nights are: 0 calm, 1 normal, 2 deadly (how many monsters, how quickly they come)
	var nightDanger: Int = 1
	/// how wiring is drawn: 0 only while a wiring tool or the probe is in hand, 1 always, 2 always but faint
	var showWires: Int = 0
	/// structural physics: built blocks need support and can only carry so much (see updateStructures)
	var structural: Bool = false
	/// vehicles take damage (shots, blasts, crashes) and parts break off
	var vehicleDamage: Bool = true

	var shakeScale: Double { return shakeOn ? shakeIntensity : 0 }

	mutating func resetWeather() {
		let d: Settings = Settings()
		weatherOn = d.weatherOn
		allowRain = d.allowRain
		allowThunder = d.allowThunder
		allowWind = d.allowWind
		allowTornado = d.allowTornado
		allowHurricane = d.allowHurricane
		allowBlizzard = d.allowBlizzard
		allowHail = d.allowHail
		weatherHurtsPlayer = d.weatherHurtsPlayer
		weatherHurtsBlocks = d.weatherHurtsBlocks
		weatherHurtsCreatures = d.weatherHurtsCreatures
		weatherIntensity = d.weatherIntensity
		severeFrequency = d.severeFrequency
		weatherAlerts = d.weatherAlerts
		weatherParticles = d.weatherParticles
		reduceFlashes = d.reduceFlashes
	}

	static let cameraDefaults: Settings = Settings()

	mutating func resetCamera() {
		let d: Settings = Settings.cameraDefaults
		camSmoothOn = d.camSmoothOn
		camFollow = d.camFollow
		camDeadZone = d.camDeadZone
		camLookAhead = d.camLookAhead
		camDirect = d.camDirect
		shakeOn = d.shakeOn
		shakeIntensity = d.shakeIntensity
		tilePx = d.tilePx
	}

	init() {}

	// Missing keys (settings saved by an older version) fall back to the defaults
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		hair = (try? c.decodeIfPresent(Int.self, forKey: .hair)) ?? 0
		scarf = (try? c.decodeIfPresent(Int.self, forKey: .scarf)) ?? 0
		hairStyle = (try? c.decodeIfPresent(Int.self, forKey: .hairStyle)) ?? 0
		shirtColor = (try? c.decodeIfPresent(Int.self, forKey: .shirtColor)) ?? 0
		shirtStyle = (try? c.decodeIfPresent(Int.self, forKey: .shirtStyle)) ?? 0
		pantsColor = (try? c.decodeIfPresent(Int.self, forKey: .pantsColor)) ?? 0
		pantsStyle = (try? c.decodeIfPresent(Int.self, forKey: .pantsStyle)) ?? 0
		// settings from before the look had styles: their hair and scarf lists were in another order,
		// so the look starts afresh as the player's own drawing (black hair, no scarf)
		if (try? c.decodeIfPresent(Int.self, forKey: .hairStyle)) == nil {
			hair = 0
			scarf = 0
		}
		touchControls = (try? c.decodeIfPresent(Bool.self, forKey: .touchControls)) ?? true
		peaceful = (try? c.decodeIfPresent(Bool.self, forKey: .peaceful)) ?? false
		showCoords = (try? c.decodeIfPresent(Bool.self, forKey: .showCoords)) ?? true
		tilePx = (try? c.decodeIfPresent(Int.self, forKey: .tilePx)) ?? 24
		rareChance = (try? c.decodeIfPresent(Double.self, forKey: .rareChance)) ?? 0.28
		smoothLight = (try? c.decodeIfPresent(Bool.self, forKey: .smoothLight)) ?? true
		fps60 = (try? c.decodeIfPresent(Bool.self, forKey: .fps60)) ?? true
		showFPS = (try? c.decodeIfPresent(Bool.self, forKey: .showFPS)) ?? false
		camSmoothOn = (try? c.decodeIfPresent(Bool.self, forKey: .camSmoothOn)) ?? true
		camFollow = (try? c.decodeIfPresent(Double.self, forKey: .camFollow)) ?? 0.55
		camDeadZone = (try? c.decodeIfPresent(Double.self, forKey: .camDeadZone)) ?? 0.8
		camLookAhead = (try? c.decodeIfPresent(Bool.self, forKey: .camLookAhead)) ?? true
		camDirect = (try? c.decodeIfPresent(Bool.self, forKey: .camDirect)) ?? false
		shakeOn = (try? c.decodeIfPresent(Bool.self, forKey: .shakeOn)) ?? true
		shakeIntensity = (try? c.decodeIfPresent(Double.self, forKey: .shakeIntensity)) ?? 0.5
		showTrajectory = (try? c.decodeIfPresent(Bool.self, forKey: .showTrajectory)) ?? true
		soundOn = (try? c.decodeIfPresent(Bool.self, forKey: .soundOn)) ?? true
		sfxVolume = (try? c.decodeIfPresent(Double.self, forKey: .sfxVolume)) ?? 0.7
		ambienceVolume = (try? c.decodeIfPresent(Double.self, forKey: .ambienceVolume)) ?? 0.5
		weatherOn = (try? c.decodeIfPresent(Bool.self, forKey: .weatherOn)) ?? true
		allowRain = (try? c.decodeIfPresent(Bool.self, forKey: .allowRain)) ?? true
		allowThunder = (try? c.decodeIfPresent(Bool.self, forKey: .allowThunder)) ?? true
		allowWind = (try? c.decodeIfPresent(Bool.self, forKey: .allowWind)) ?? true
		allowTornado = (try? c.decodeIfPresent(Bool.self, forKey: .allowTornado)) ?? true
		allowHurricane = (try? c.decodeIfPresent(Bool.self, forKey: .allowHurricane)) ?? true
		allowBlizzard = (try? c.decodeIfPresent(Bool.self, forKey: .allowBlizzard)) ?? true
		allowHail = (try? c.decodeIfPresent(Bool.self, forKey: .allowHail)) ?? true
		weatherHurtsPlayer = (try? c.decodeIfPresent(Bool.self, forKey: .weatherHurtsPlayer)) ?? true
		weatherHurtsBlocks = (try? c.decodeIfPresent(Bool.self, forKey: .weatherHurtsBlocks)) ?? true
		weatherHurtsCreatures = (try? c.decodeIfPresent(Bool.self, forKey: .weatherHurtsCreatures)) ?? true
		weatherIntensity = clampD((try? c.decodeIfPresent(Double.self, forKey: .weatherIntensity)) ?? 1.0, 0.25, 1.5)
		severeFrequency = clampI((try? c.decodeIfPresent(Int.self, forKey: .severeFrequency)) ?? 1, 0, 2)
		weatherAlerts = (try? c.decodeIfPresent(Bool.self, forKey: .weatherAlerts)) ?? true
		weatherParticles = clampD((try? c.decodeIfPresent(Double.self, forKey: .weatherParticles)) ?? 1.0, 0.2, 1.0)
		reduceFlashes = (try? c.decodeIfPresent(Bool.self, forKey: .reduceFlashes)) ?? false
		nightDanger = clampI((try? c.decodeIfPresent(Int.self, forKey: .nightDanger)) ?? 1, 0, 2)
		showWires = clampI((try? c.decodeIfPresent(Int.self, forKey: .showWires)) ?? 0, 0, 2)
		structural = (try? c.decodeIfPresent(Bool.self, forKey: .structural)) ?? false
		vehicleDamage = (try? c.decodeIfPresent(Bool.self, forKey: .vehicleDamage)) ?? true
	}
}

/// The HUD and panels watch this instead of the whole game, so they only redraw when something they show changes.
final class HUDSignal: ObservableObject, @unchecked Sendable {
	@Published var tick: Int = 0
}

/// The world canvas watches this; it changes once per game step.
final class FrameTicker: ObservableObject, @unchecked Sendable {
	@Published var frame: Int = 0
}

struct IntPair: Hashable {
	var x: Int
	var y: Int
}

final class Game: ObservableObject, @unchecked Sendable {
	/// a number no other game in this run has (what the render cache knows a world by)
	let serial: Int = Game.nextSerial()
	static var serialCount: Int = 0
	static func nextSerial() -> Int {
		serialCount += 1
		return serialCount
	}
	// UI refresh signals
	let hud: HUDSignal = HUDSignal()
	let ticker: FrameTicker = FrameTicker()
	var lastHudKey: Int = 0
	var renderFPS: Double = 0
	@Published var showInventory: Bool = false
	@Published var showDebug: Bool = false
	@Published var showMap: Bool = false
	@Published var showJournal: Bool = false
	@Published var paused: Bool = false
	@Published var openChest: IntPair? = nil
	@Published var message: String? = nil
	@Published var dead: Bool = false
	@Published var craftStation: Station = .hand

	// setup
	var world: World
	var settings: Settings
	var mode: GameMode
	var worldName: String = "World"
	var slot: Int = 0
	var seedValue: UInt64

	// time
	var timeOfDay: Double = 0.06
	/// seconds of a whole day (12 minutes, or a mod's day length rule)
	var dayLength: Double { return 60.0 * ModRuntime.shared.rule(.day) }
	var dayCount: Int = 1
	var clock: Double = 0
	var playSeconds: Double = 0
	var messageT: Double = 0
	var hudAccum: Int = 0

	// player
	var pb: Body
	var facing: Int = 1
	var hp: Double = 20
	var maxHP: Double = 20
	var hunger: Double = 20
	var air: Double = 10
	var hurtT: Double = 0
	var invuln: Double = 0
	var deathT: Double = 0
	var inv: Inventory = Inventory()
	var sel: Int = 0
	var spawnX: Double = 0
	var spawnY: Double = 0
	var kills: Int = 0
	var coyote: Double = 0
	var jumpBuf: Double = 0
	var dropT: Double = 0
	/// time left in a vault out of water onto a ledge
	var vaultT: Double = 0
	var starveT: Double = 0
	var regenT: Double = 0
	var lastVy: Double = 0
	var walkAnim: Double = 0
	/// how long the player has stood still with nothing in hand at work (the sprite turns to face out
	/// of the screen after a moment)
	var restT: Double = 0
	var fallPeak: Double = 0

	// cheats / debug
	var flying: Bool = false
	var noclip: Bool = false
	var godMode: Bool = false
	var freezeTime: Bool = false
	var monstersEnabled: Bool = true
	var speedMult: Double = 1.0
	var showHitboxes: Bool = false
	/// debug: each hostile's AI state, what it knows of the player and why it is not attacking
	var showAI: Bool = false
	var showChunks: Bool = false
	var fullBright: Bool = false
	var infiniteReach: Bool = false
	/// debug: multiplies the health of newly spawned creatures
	var mobHealthMult: Double = 1.0
	/// debug: individual systems can be paused to isolate problems
	var pauseMobs: Bool = false
	var pauseBosses: Bool = false
	var pauseSpawning: Bool = false
	var pauseProjectiles: Bool = false
	var pauseVehicles: Bool = false
	var pauseWorldTicks: Bool = false
	var pauseParticles: Bool = false
	/// debug: the creature picked with "Select at cursor"
	weak var debugSelected: Mob? = nil
	/// lairs whose boss stays away until the player has left the area (after "Delete all entities")
	var suppressedLairs: Set<Int> = []

	// tool use
	var swingT: Double = 0
	var swingDur: Double = 0.25
	var swingDir: Int = 1
	var useCD: Double = 0
	var bowCharge: Double = 0
	var reloadT: Double = 0
	var reloadSlot: Int = -1
	var mineX: Int = 0
	var mineY: Int = 0
	var mineP: Double = 0
	var mining: Bool = false
	var muzzleT: Double = 0
	var recoilT: Double = 0
	var bowRecoil: Double = 0
	var eatT: Double = 0

	// input state (set by the UI layer)
	var stick: Double = 0
	var stickY: Double = 0
	var keyL: Bool = false
	var keyR: Bool = false
	var jumpHeld: Bool = false
	var jumpPrev: Bool = false
	var downHeld: Bool = false
	var useHeld: Bool = false
	var usePressedFlag: Bool = false
	var useReleasedFlag: Bool = false
	var aimX: Double = 0
	var aimY: Double = 0
	var aimValid: Bool = false
	var useWasHeld: Bool = false
	var lavaT: Double = 0
	var drownT: Double = 0
	var hardcoreOver: Bool = false
	var pendingInteract: Bool = false
	var downTime: Double = 0
	var pointerStartX: Double = 0
	var pointerStartY: Double = 0
	var carry: Stack? = nil
	var placeCD: Double = 0
	var decksCache: [Deck] = []
	var mineNeed: Double = 1

	// camera and view
	var camX: Double = 0
	/// where the camera is heading (dead zone applied); camX/camY ease toward it
	var camTX: Double = 0
	var camTY: Double = 0
	var camLead: Double = 0
	var camY: Double = 0
	var viewW: Double = 1024
	var viewH: Double = 768
	var tilePx: Int = 24
	var shake: Double = 0

	// entities
	var mobs: [Mob] = []
	var projectiles: [Projectile] = []
	var drops: [DropItem] = []
	/// doors the player walked through, closing behind them (see updateWalkDoors)
	var walkDoors: [WalkDoor] = []
	var particles: [Particle] = []
	/// leaves falling from the trees on screen (see updateLeafFall)
	var leafFlakes: [LeafFlake] = []
	var floats: [FloatText] = []
	var vehicles: [Vehicle] = []
	var ships: [PirateShip] = []
	var nextID: Int = 1
	var spawnTimer: Double = 2.0
	/// Sparkworks networks and their live state
	let power: PowerSim = PowerSim()
	/// time before the next monster may come out on the surface (sets the pace of a night)
	var monsterSpawnCD: Double = 0
	/// debug: how spawn attempts ended, by reason, and the last one
	var spawnLog: [String: Int] = [:]
	var spawnLast: String = ""
	var shipTimer: Double = 20.0
	var fallingBlocks: [FallingBlock] = []
	/// placing a held block as a wall instead (the HUD's WALL switch)
	var wallMode: Bool = false
	/// the item in hand while the use button is held, and whether that hold used it up (see updateUse)
	var lastUsedItem: Item? = nil
	var handEmptied: Bool = false
	/// the chair or sofa the player is sitting on
	var seat: IntPair? = nil
	/// a chair or sofa built on a vehicle the player sits on (the vehicle is the one they ride)
	var seatAboard: PartCell? = nil
	/// the buttons A, B and C for joints, while held; the joint being set up (its panel is open)
	var jointButtons: [Bool] = [false, false, false]
	var jointEdit: JointRef? = nil
	@Published var showJoint: Bool = false
	/// the vehicle the remote control is paired with, and the one it drives now (0: none)
	var remotePair: Int = 0
	var remoteID: Int = 0
	/// the signal channels (1 to 8 as the player sees them): on from powered signal posts (worked out
	/// with the machines), or as the Logic Studio set them
	var channels: [Bool] = [Bool](repeating: false, count: Radio.channels)
	var postChannels: [Bool] = [Bool](repeating: false, count: Radio.channels)
	var logicChannels: [Bool] = [Bool](repeating: false, count: Radio.channels)
	/// the vehicle whose receiver is being set up (its panel is open)
	var radioEdit: Int = 0
	@Published var showRadio: Bool = false
	/// doors on vehicles the player opened by walking into them
	var vehicleDoors: [VehicleDoor] = []
	/// the lift cars of this dimension, and those left in the others
	var lifts: [Lift] = []
	var liftStash: [[Lift]] = [[Lift]](repeating: [], count: dimCount)
	/// structural physics: changes waiting to be looked at, a moment's wait to gather them, and the
	/// blocks under strain (drawn cracked)
	var structQueue: [IntPair] = []
	var structT: Double = 0
	var stress: [Int: Double] = [:]
	var decayZones: [DecayZone] = []
	/// short-lived lights from explosions (fed into the light map as moving lights, then removed)
	var flashes: [LightFlash] = []
	/// ground about to be struck by a telegraphed attack (drawn as a warning)
	var dangerZones: [DangerZone] = []
	var journal: Journal = Journal()
	var discoverT: Double = 0
	var guardianT: Double = 0
	/// weather (see WeatherSim): the simulation, what it brings to where the player stands, and the
	/// short-lived things it puts in the world
	var weather: WeatherSim = WeatherSim()
	var wxHere: LocalWeather = LocalWeather()
	/// kept for the code that reads them: how hard rain or snow falls on the player, and whether it is snow
	var weatherRain: Double = 0
	var weatherSnow: Bool = false
	/// where the player last stood in the overworld (the weather is judged there while they are away)
	var wxHomeX: Double = 0
	var coastCache: [Int: (Double, Double)] = [:]
	var bolts: [LightningBolt] = []
	var thunderQueue: [PendingThunder] = []
	var strikeMark: StrikeMark? = nil
	var strikeAcc: Double = 0
	var playerStrikeCD: Double = 0
	var skyFlash: Double = 0
	var hailPool: [HailStone] = []
	var hailAcc: Double = 0
	var hailHitT: Double = 0
	var hailBroken: Int = 0
	/// how much warmth the player has lost to the cold (0 fine ... 1 freezing), and what keeps it in
	var bodyCold: Double = 0
	var coldHurtT: Double = 0
	var coldWarned: Bool = false
	var warmthNear: Double = 0
	var warmthT: Double = 0
	/// 0 open, 1 under a roof, 2 indoors, 3 underground or in a storm shelter (see shelterAt)
	var shelterLevel: Int = 0
	var wxCellT: Double = 0
	/// the wind's hold on the player this frame (see updateWeatherForces)
	var wxWalk: Double = 0
	var wxAirDrift: Double = 0
	var wxRest: Double = 0
	var wxAccelX: Double = 0
	var wxAccelY: Double = 0
	var wxSlip: Double = 0
	var wxSlow: Double = 1
	/// thrown by a tornado: a hard landing hurts less
	var flingT: Double = 0
	var wxDebrisT: Double = 0
	var tornadoAcc: Double = 0
	var tornadoGround: Double = 0
	var hurricaneAcc: Double = 0
	var surgeT: Double = 0
	/// time not yet spent on the liquids' flow (see updateFlow), and the beat of a mod liquid's harm
	var flowAccum: Double = 0
	var liquidHarmT: Double = 0
	var swampT: Double = 0
	var wxDevT: Double = 0
	var wxNoteT: Double = 0
	/// the present severe spell actually reached the player (it then goes in the journal)
	var stormFelt: Bool = false
	var sirenLevel: Double = 0
	/// the warning strip under the top bar (0 none, 1 advisory, 2 warning)
	var wxBanner: String = ""
	var wxBannerLevel: Int = 0
	/// the weather station whose screen is open
	var stationAt: DeviceSpot? = nil
	@Published var showWeather: Bool = false
	/// a Sparkworks device's panel, and which device
	@Published var showPower: Bool = false
	var powerAt: ChestKey? = nil
	/// the last cell a wire drag reached, the network the probe lit up
	var wireLast: IntPair? = nil
	var wireSoundT: Double = 0
	var inspect: PowerInspect? = nil
	/// the landing squash and the last frame's water state (for splashes)
	var landT: Double = 0
	var wasInWater: Bool = false
	let mobGrid: MobGrid = MobGrid()
	var frameNo: Int = 0

	// combat: the blow a heavy weapon is winding up, the brief freeze when a hit lands, the foe the
	// aim is locked onto, a knife's run of quick hits, the trails, lightning and fire on screen
	var strikeT: Double = 0
	var strikeSel: Int = -1
	var strikeItem: Item? = nil
	weak var strikeTarget: Mob? = nil
	var hitStopT: Double = 0
	weak var lockTarget: Mob? = nil
	var lockT: Double = 0
	var comboN: Int = 0
	var comboT: Double = -10
	var slashes: [SlashFX] = []
	var arcs: [ArcFX] = []
	var fireZones: [FireZone] = []
	var rodT: Double = 0
	/// a finger is on the world (it aims for itself; the action button only keeps the action going)
	var touchActive: Bool = false
	/// a panel, the pause menu or death is covering the controls (their held state is dropped)
	var inputBlocked: Bool = false
	var lastWeaponSel: Int = -1
	/// what the last melee blow hit (for the feedback and the tests)
	var lastStrikeHits: Int = 0

	// damage bookkeeping
	var playerHitStamps: [Int: Double] = [:]
	var playerBurn: Double = 0
	var playerBurnTick: Double = 0
	/// the mods this world uses (see ModRuntime; nil for a world without mods)
	var modInfo: ModWorldInfo? = nil
	/// the id of the mod being tried out in a mod test world ("" in a real world)
	var testMod: String = ""
	/// structure capture: picking two corners on the world, then the save panel (see startCapture)
	@Published var capturing: Bool = false
	@Published var showCapture: Bool = false
	/// the Mod Test tools (test worlds only)
	@Published var showModTest: Bool = false
	var capA: (Int, Int)? = nil
	var capB: (Int, Int)? = nil
	/// effects from potions, food and armour (see PlayerEffects)
	var effects: PlayerEffects = PlayerEffects()
	/// seconds before mending potions heal fully again
	var mendCD: Double = 0
	/// smoke clouds and the rings of bursting potions
	var smokes: [SmokeCloud] = []
	var rings: [BurstRing] = []
	/// the exosuit, a counter bumped whenever it changes, and the numbers worked out from it
	var suit: ExoSuit = ExoSuit()
	var suitRev: Int = 0
	var suitStatsRev: Int = -1
	var suitStatsCache: ExoStats = ExoStats()
	/// energy a second the suit's running modules are drawing this frame, and what is running
	var suitLoad: Double = 0
	var suitLastLoad: Double = 0
	var suitHover: Bool = false
	/// the suit's guns: each one's wait before it can fire again (by piece), the lasers' beams this frame,
	/// whether its FIRE control is held, and when it may next say a piece broke
	var suitGunCD: [Int: Double] = [:]
	var suitBeams: [(Double, Double, Double, Double)] = []
	var suitFireHeld: Bool = false
	var suitSayT: Double = 0
	var suitSprinting: Bool = false
	var suitLit: Bool = false
	var suitEmptyWarned: Bool = false
	/// armour infusions summed over what is worn, and the key of what was worn then
	var armorInfCache: ArmorInf = ArmorInf()
	var armorInfKey: Int = 0
	@Published var showInfuse: Bool = false
	/// when each custom infusion last gave its effect (by number)
	var infTriggerCD: [Int: Double] = [:]
	@Published var showExo: Bool = false
	/// a healing shrine rests between uses
	var healerCD: Double = 0
	/// debug multipliers: damage the player deals / takes
	var dmgOutMult: Double = 1.0
	var dmgInMult: Double = 1.0

	// lighting
	var light: LightMap = LightMap()
	/// the light around a spot a creature might appear at (see glowForSpawn)
	let spawnLight: LightMap = LightMap()
	var lightDark: [UInt32] = []
	var lightGlow: [UInt32] = []
	var lightRev: Int = 0
	var lightTimer: Double = 0

	// bosses & progress
	var defeated: Set<Int> = []
	var rex: Mob? = nil
	var activeBoss: Mob? = nil
	var bossBarName: String = ""
	var bossBarFrac: Double = 0
	var gotMap: Bool = false
	var portalOpened: Bool = false
	var portalT: Double = 0
	var portalCool: Double = 0
	/// set by a portal trip: the rift will not pull the player again until they have stepped out of it
	var portalNeedsExit: Bool = false
	var riftCheckT: Double = 0
	var fadeT: Double = 0
	var mounted: Mob? = nil
	var inVehicle: Vehicle? = nil
	/// the places a vehicle touches the land in the physics step being worked out (kept to save making a list each step)
	var vContacts: [VContact] = []
	/// the ON VEHICLE switch: blocks in hand are built onto the nearest vehicle instead of the world
	var vehicleBuild: Bool = false
	/// fuel tanks that burst this frame (they go off next frame, so one blast cannot run into itself)
	var vehBlasts: [(Double, Double)] = []
	/// keeps vehicle warnings (out of ammunition and the like) from repeating every frame
	var vehSayT: Double = 0
	var vehicleStash: [[Vehicle]] = [[Vehicle]](repeating: [], count: dimCount)
	/// where the player came from into a custom dimension (to go back there)
	var dimReturn: DimReturn? = nil
	/// the Logic Studio's running scripts, and the variables of the world's mods ("mod:name")
	var logic: LogicVM = LogicVM()
	var logicVars: [String: Double] = [:]
	var mapCache: TreasureMap? = nil
	var hintT: Double = 0
	var autosaveT: Double = 0

	// streaming stats
	var loadRadius: Int = 5
	var lastStreamCX: Int = Int.min
	var chunksLoadedLast: Int = 0
	var tickMs: Double = 0
	var tickWorstMs: Double = 0

	/// A new world, with the land around its spawn made. A world being loaded passes `loadSpawn: false`:
	/// its land comes from the save, around where the player was (making the spawn's land first only
	/// to throw it away cost a dozen chunks every time a world was loaded).
	init(mode: GameMode, infinite: Bool, seed: UInt64, settings: Settings, genVersion: Int = WorldGen.currentVersion, options: WorldOptions = .standard, loadSpawn: Bool = true) {
		self.mode = mode
		self.settings = settings
		self.seedValue = seed
		let gen = WorldGen(seed: seed, infinite: infinite, rareChance: settings.rareChance, genVersion: genVersion, options: options)
		self.world = World(gen: gen)
		self.tilePx = settings.tilePx
		self.pb = Body(x: Double(gen.spawnX) + 0.5, y: 100, w: 0.7, h: 1.8)
		if loadSpawn {
			world.loadAround(centerX: gen.spawnX, radius: 6)
			let sy: Int = world.surfaceY(gen.spawnX)
			pb.y = Double(sy)
		}
		spawnX = pb.x
		spawnY = pb.y
		camX = pb.x
		camY = pb.y - 2
		setupStartingKit()
		timeOfDay = 0.06
		// the weather has its own random numbers, started from the world's seed
		weather.rngS = seed ^ 0x57EA_7E12_9B3D_0451
		weather.fxS = seed ^ 0x0FF5_E7FA_CE12_7731
		wxHomeX = pb.x
	}

	func setupStartingKit() {
		applyHealthRule(newWorld: true)
		if mode == .creative {
			flying = false
			return
		}
		_ = inv.add(.block(.torch), 4)
		giveStartItems()
	}

	var gen: WorldGen { return world.gen }
	var isCreative: Bool { return mode == .creative }
	var viewTilesW: Double { return viewW / Double(tilePx) }
	var viewTilesH: Double { return viewH / Double(tilePx) }

	func newID() -> Int {
		nextID += 1
		return nextID
	}

	func say(_ s: String, _ t: Double = 3.0) {
		message = s
		messageT = t
		hud.tick &+= 1
	}

	func bumpHUD() {
		hud.tick &+= 1
	}

	// MARK: time of day

	/// 1 = full day, 0 = deep night
	var dayFactor: Double {
		let t: Double = timeOfDay
		if world.dim != .overworld {
			if let d = customDim, !d.def.ceiling { return customDayFactor(d) }
			return 0
		}
		if t < 0.50 { return 1.0 }
		if t < 0.58 { return 1.0 - smooth((t - 0.50) / 0.08) }
		if t < 0.92 { return 0.0 }
		return smooth((t - 0.92) / 0.08)
	}

	/// How bright the open sky is (0 dark ... 15 noon): night light from the moon, daylight from the sun
	/// (a mod's sun or moon can give more or less of it)
	var skyLevel: Int {
		if world.dim != .overworld {
			guard let d = customDim, !d.def.ceiling else { return 0 }
			// a sun or moon switched off still lights the sky as the game's would
			let sb: Double = d.def.sun ? (d.def.sunBody?.bright ?? 1.0) : 1.0
			let mb: Double = d.def.moon ? (d.def.moonBody?.bright ?? 1.0) : 1.0
			let lv: Double = clampD(d.def.light, 0, 1) * skyLight(sb, mb)
			return Int(clampD(lv, 0, 15).rounded())
		}
		let rt: ModRuntime = ModRuntime.shared
		if rt.overSun == nil && rt.overMoon == nil { return Int((6.0 + 9.0 * dayFactor).rounded()) }
		let lv: Double = skyLight(rt.overSun?.bright ?? 1.0, rt.overMoon?.bright ?? 1.0)
		return Int(clampD(lv, 0, 15).rounded())
	}

	/// Open sky's light (15 at noon, 6 at midnight with the game's sun and moon): a sun's brightness
	/// scales the daylight it adds, a moon's the light of the night (never the day's)
	func skyLight(_ sun: Double, _ moon: Double) -> Double {
		let nights: Double = ModRuntime.shared.rule(.nights)
		let night: Double = 6.0 * (dayFactor + (1.0 - dayFactor) * moon * nights)
		return night + 9.0 * dayFactor * sun
	}

	var isNight: Bool { return dayFactor < 0.35 }

	// MARK: items

	func giveItem(_ it: Item, _ n: Int, extra: Int = 0) {
		let left: Int = inv.add(it, n, extra: extra)
		if left > 0 {
			spawnDrop(Stack(item: it, count: left, extra: extra), pb.x, pb.y - 1.0, Double(facing) * 3.0, -4.0)
		}
		bumpHUD()
	}

	func spawnDrop(_ s: Stack, _ x: Double, _ y: Double, _ vx: Double, _ vy: Double, heldBack: Bool = false) {
		if s.count <= 0 { return }
		var d: DropItem = DropItem(stack: s, x: x, y: y, vx: vx, vy: vy)
		d.heldBack = heldBack
		drops.append(d)
	}

	func spawnParticles(_ x: Double, _ y: Double, _ color0: UInt32, _ n: Int, _ speed: Double, _ life: Double = 0.6, _ grav: Double = 18) {
		if particles.count > 160 { return }
		let color: UInt32 = artGrade(color0)
		for _ in 0..<n {
			let a: Double = Double.random(in: 0...(2 * Double.pi))
			let s: Double = Double.random(in: 0.3...1.0) * speed
			particles.append(Particle(x: x, y: y, vx: cos(a) * s, vy: sin(a) * s - speed * 0.3, life: life * Double.random(in: 0.6...1.2), maxLife: life, color: color, size: Double.random(in: 0.08...0.18), gravity: grav))
		}
	}

	func floatText(_ s: String, _ x: Double, _ y: Double, _ color: UInt32 = 0xFFFFFF) {
		if floats.count > 14 { floats.removeFirst() }
		floats.append(FloatText(x: x, y: y, text: s, life: 1.0, color: color))
	}

	// MARK: selected item helpers

	var heldStack: Stack? { return inv.slots[sel] }
	var heldItem: Item? { return inv.slots[sel]?.item }

	func setSel(_ i: Int) {
		let n: Int = clampI(i, 0, Inventory.hotbarCount - 1)
		if n != sel, let it = heldItem, it.isWeapon { lastWeaponSel = sel }
		// switching while the attack control is down must not fire the new weapon in the same instant
		if n != sel && actState.held { useCD = max(useCD, 0.15) }
		sel = n
		bowCharge = 0
		mining = false
		mineP = 0
		// a blow being wound up is dropped with the weapon; a knife's run starts over
		strikeT = 0
		comboN = 0
		bumpHUD()
	}

}

// ===== p14b_player =====

// MARK: - Master tick, player movement, survival, camera, streaming, lighting

extension Game {
	func tick(_ rawDt: Double) {
		if paused { return }
		let dt: Double = min(max(rawDt, 0.001), 0.05) * (freezeTime ? 1.0 : 1.0)
		let t0: Double = Date().timeIntervalSinceReferenceDate
		clock += dt
		if !dead { playSeconds += dt }
		if messageT > 0 {
			messageT -= dt
			if messageT <= 0 { message = nil }
		}
		updateTime(dt)
		updateInputGate()
		mobGrid.rebuild(mobs)
		updateLifts(dt)
		decksCache = (ships.isEmpty && lifts.isEmpty) ? [] : buildDecks()
		updatePointerTimers(dt)
		updateInputEdges()
		updatePlayer(dt)
		updateUse(dt)
		updateEffects(dt)
		updateModPlay(dt)
		updateLogic(dt)
		// a landed blow holds the creatures still for a frame or two (the player keeps moving), which
		// is what makes a hit feel like it connected
		let frozen: Bool = hitStopT > 0
		if frozen { hitStopT -= dt }
		if !pauseMobs && !frozen { updateMobs(dt) }
		updateDangerZones(dt)
		updateDiscoveries(dt)
		if !pauseBosses && !frozen { updateBosses(dt) }
		if !pauseSpawning { updateSpawning(dt) }
		if !pauseProjectiles { updateProjectiles(dt) }
		updateCombatFX(dt)
		if !pauseWorldTicks {
			updateFallingBlocks(dt)
			updateStructures(dt)
			updateFlow(dt)
		}
		updateDrops(dt)
		if !pauseVehicles { updateVehicles(dt) }
		// everybody aboard a vehicle is where it now has them
		syncRiders()
		if !pauseMobs { updateShips(dt) }
		if !pauseWorldTicks { updateWorldTicks(dt) }
		updatePortal(dt)
		updateAutosave(dt)
		if !pauseParticles {
			updateParticles(dt)
			updateLeafFall(dt)
		}
		updateFlashes(dt)
		updateWeather(dt)
		if !pauseWorldTicks { updatePower(dt) }
		updatePowerUI(dt)
		updateAudio()
		updateStreaming()
		updateCamera(dt)
		updateLight(dt)
		hudAccum += 1
		if hudAccum >= 5 {
			hudAccum = 0
			let k: Int = hudKey()
			if k != lastHudKey || showDebug {
				lastHudKey = k
				hud.tick &+= 1
			}
		}
		let t1: Double = Date().timeIntervalSinceReferenceDate
		tickMs = tickMs * 0.9 + (t1 - t0) * 1000.0 * 0.1
		tickWorstMs = max(tickWorstMs * 0.995, (t1 - t0) * 1000.0)
		Perf.shared.endFrame()
	}

	/// Screen shake, scaled (or disabled) by the camera settings
	func addShake(_ amount: Double) {
		shake = max(shake, amount * settings.shakeScale)
	}

	func updateTime(_ dt: Double) {
		if freezeTime { return }
		// the world's clock runs on in a custom dimension with day and night (it used to stop there,
		// so a dimension entered at night stayed dark for good)
		if world.dim != .overworld {
			guard let d = customDim, d.def.cycle, !d.def.ceiling else { return }
		}
		timeOfDay += dt / dayLength
		if timeOfDay >= 1.0 {
			timeOfDay -= 1.0
			dayCount += 1
		}
	}

	func updateInputEdges() {
		if useHeld && !usePressedFlag && !useWasHeld { usePressedFlag = true }
		useWasHeld = useHeld
	}

	// MARK: player

	func updatePlayer(_ dt: Double) {
		if dead {
			deathT += dt
			return
		}
		if invuln > 0 { invuln -= dt }
		if hurtT > 0 { hurtT -= dt }
		if shake > 0 { shake = max(0, shake - dt * 1.5) }
		var ix: Double = stick
		if keyL { ix -= 1.0 }
		if keyR { ix += 1.0 }
		ix = clampD(ix, -1.0, 1.0)
		if abs(ix) < 0.08 { ix = 0 }
		var jumpPressed: Bool = jumpHeld && !jumpPrev
		jumpPrev = jumpHeld
		if remoteID != 0 {
			if let rv = remoteVehicle, remoteCanReach(rv) {
				driveRemote(rv, ix, jumpPressed, dt)
			} else {
				endRemote("The remote lost the vehicle.")
			}
			// (the player's hands are on the remote: they stand where they are)
			ix = 0
			jumpPressed = false
		}
		if let v = inVehicle {
			driveVehicle(v, ix, jumpPressed, dt)
			return
		}
		if let r = mounted {
			rideRex(r, ix, jumpPressed, dt)
			return
		}
		if seat != nil && stayInSeat(ix, jumpPressed) {
			lastVy = 0
			return
		}
		if seatAboard != nil && stayInSeatAboard(ix, jumpPressed) {
			lastVy = 0
			return
		}
		var runMax: Double = 7.4 * speedMult * ModRuntime.shared.rule(.walk) * (wearing(.swiftBoots) ? 1.18 : 1.0) * wxSlow * (1.0 + effects.value(.speed) / 100.0) * (1.0 + armorInf.speed) * suitSpeedMul
		// heavy weapons commit you to the blow: slower on your feet while it lasts
		if swingT > 0 || strikeT > 0, let it = heldItem, it.isMeleeWeapon { runMax *= it.melee.moveScale }
		// a mod's sticky block holds the player back
		let sticky: Bool = inStickyBlock()
		if sticky { runMax *= 0.35 }
		if ix != 0 {
			facing = ix > 0 ? 1 : -1
		}
		if swingT > 0 || useHeld {
			if aimValid {
				facing = aimFacing()
			}
		}
		if flying || noclip {
			let tx: Double = ix * 13.0 * speedMult
			var ty: Double = 0
			if jumpHeld { ty = -10.0 }
			if downHeld || stickY > 0.55 { ty = 10.0 }
			pb.vx += (tx - pb.vx) * min(1.0, dt * 9.0)
			pb.vy += (ty - pb.vy) * min(1.0, dt * 9.0)
			if noclip {
				pb.x += pb.vx * dt
				pb.y += pb.vy * dt
			} else {
				world.moveBody(&pb, dt, stepUp: 0, dropThrough: true, decks: [])
			}
			walkAnim += abs(pb.vx) * dt * 0.5
			lastVy = pb.vy
			checkHazards(dt)
			return
		}
		let inWater: Bool = pb.inWater
		let inLava: Bool = pb.inLava
		// climbing out of water: pushing against a bank or a ledge with jump held vaults onto it, if the
		// top is within reach (water used to pin the player under any ledge above its surface). Decided
		// before swimming, so the swim limits on rising speed do not cancel the vault.
		if (inWater || inLava) && vaultT <= 0 && jumpHeld && ix != 0 && pb.hitWall && ledgeWithinReach(ix > 0 ? 1 : -1) {
			vaultT = 0.32
			pb.vy = -13.0
		}
		if vaultT > 0 { vaultT -= dt }
		let swimming: Bool = (inWater || inLava) && vaultT <= 0
		// ladders: while the body overlaps one the player climbs (jump or up to climb, down to descend)
		if !swimming, let lc = ladderSpot() {
			let climbUp: Bool = jumpHeld || stickY < -0.45
			let climbDown: Bool = downHeld || stickY > 0.45
			let vyT: Double = climbUp ? -5.2 : (climbDown ? 5.2 : 0.0)
			pb.vy += (vyT - pb.vy) * min(1.0, dt * 16.0)
			var tx: Double = ix * runMax * 0.7
			// while climbing with no sideways input the body settles onto the rungs
			if ix == 0 && (climbUp || climbDown) { tx = (lc - (pb.ride != 0 ? pb.rlx : pb.x)) * 8.0 }
			pb.vx += (tx - pb.vx) * min(1.0, dt * 14.0)
			moveThing(&pb, dt, stepUp: 1.0, dropThrough: climbDown, decks: allDecks(), mass: playerMass, falls: false)
			coyote = 0.11
			jumpBuf = 0
			fallPeak = 0
			walkAnim += (abs(pb.vy) + abs(pb.vx)) * dt * 0.55
			lastVy = pb.vy
			checkHazards(dt)
			updateSurvival(dt, ix)
			return
		}
		// the wind (see updateWeatherForces) helps or holds back a walk, carries a jump, and in a gale
		// pushes even a player standing still; snow and wet ground make the footing slippery. All of
		// these are zero in calm weather, so movement is then exactly as it always was.
		let windT: Double = swimming ? 0 : (pb.onGround ? wxWalk : wxAirDrift)
		let swimMul: Double = (effects.value(.breathing) > 0 && !inLava) ? 0.85 : 0.55
		let target: Double = ix * runMax * (swimming ? swimMul : 1.0) + (ix != 0 ? windT : 0)
		let grip: Double = pb.onGround ? 1.0 - 0.6 * wxSlip : 1.0
		let accel: Double = (pb.onGround ? 72.0 : 40.0) * grip
		if ix != 0 {
			if pb.vx < target { pb.vx = min(target, pb.vx + accel * dt) } else { pb.vx = max(target, pb.vx - accel * dt) }
		} else {
			let rest: Double = swimming ? 0 : (pb.onGround ? wxRest : wxAirDrift)
			let fr: Double = (pb.onGround ? 90.0 * (1.0 - 0.8 * wxSlip) : 12.0) * dt
			if pb.vx > rest { pb.vx = max(rest, pb.vx - fr) } else { pb.vx = min(rest, pb.vx + fr) }
		}
		// a tornado's pull and lift (bounded; zero without one)
		if wxAccelX != 0 || wxAccelY != 0 {
			pb.vx = clampD(pb.vx + wxAccelX * dt, -16, 16)
			pb.vy = clampD(pb.vy + wxAccelY * dt, -14, terminalV)
			if wxAccelY < -8 { pb.onGround = false }
		}
		if pb.onGround { coyote = 0.11 } else { coyote -= dt }
		if jumpPressed { jumpBuf = 0.13 } else { jumpBuf -= dt }
		if jumpBuf > 0 && coyote > 0 && !swimming {
			// a jump boost raises the jump's height by its percentage
			pb.vy = -15.9 * sqrt((1.0 + effects.value(.jump) / 100.0) * ModRuntime.shared.rule(.jump)) * suitJumpMul()
			coyote = 0
			jumpBuf = 0
			pb.onGround = false
			spawnParticles(pb.x, pb.y, 0xB0A890, 4, 2.5, 0.35, 10)
		}
		if swimming {
			pb.vy += (inLava ? 14.0 : 11.0) * dt
			if jumpHeld { pb.vy = max(pb.vy - 52.0 * dt, -6.5) }
			pb.vy = clampD(pb.vy, -8.0, inLava ? 3.0 : 6.0)
		} else {
			var g: Double = gravityG
			if !jumpHeld && pb.vy < -5.0 { g *= 2.6 }
			pb.vy = min(pb.vy + g * dt, terminalV)
		}
		if sticky {
			pb.vy = clampD(pb.vy, -5.0, 2.2)
			fallPeak = 0
		}
		if (downHeld || stickY > 0.6) { dropT = 0.22 }
		if dropT > 0 { dropT -= dt }
		let decks: [Deck] = allDecks()
		let wasAir: Bool = !pb.onGround
		let peak: Double = pb.vy
		moveThing(&pb, dt, stepUp: 1.0, dropThrough: dropT > 0, decks: decks, mass: playerMass, falls: !swimming)
		if pb.deck >= 0 && pb.deck < decks.count {
			let dk: Deck = decks[pb.deck]
			pb.x += dk.vx * dt
		}
		doorTouch(ix)
		updateWalkDoors(dt)
		vehicleDoorTouch(ix)
		updateVehicleDoors(dt)
		if !pb.onGround && pb.vy > 0 { fallPeak = max(fallPeak, pb.vy) }
		if pb.onGround && wasAir {
			if fallPeak > 20.0 && !swimming && mode != .creative && !godMode {
				var dmg: Double = (fallPeak - 20.0) * 1.15 * ModRuntime.shared.rule(.falls)
				// thrown by a tornado: a hard landing, but one that can be lived through
				if flingT > 0 { dmg = settings.weatherHurtsPlayer ? min(dmg, 3.0) : 0 }
				if dmg > 0 { damagePlayer(dmg, from: pb.x, knock: 0, ignoreArmor: true) }
				addShake(0.3)
			}
			if fallPeak > 9.0 { spawnParticles(pb.x, pb.y, 0xB0A890, 6, 3.0, 0.4, 10) }
			if fallPeak > 6.0 { sfx(.land, clampD((fallPeak - 6.0) / 14.0, 0.2, 1.0)); landT = 0.12 }
			fallPeak = 0
		}
		if pb.onGround || swimming { fallPeak = 0 }
		_ = peak
		walkAnim += abs(pb.vx) * dt * 0.55
		let still: Bool = pb.onGround && abs(pb.vx) < 0.15 && abs(ix) < 0.1 && swingT <= 0 && !mining && bowCharge <= 0 && hurtT <= 0
		restT = still && seat == nil ? restT + dt : 0
		lastVy = pb.vy
		checkHazards(dt)
		updateSurvival(dt, ix)
	}

	/// Column of a ladder the body is on (its centre within a third of a block of the ladder), or nil.
	/// The tile right under the feet counts too, so a climb carries on until the player stands at the
	/// top, and a ladder going down a hole can be walked across.
	func ladderColumn() -> Int? {
		let cx: Int = Int(floor(pb.x))
		let frac: Double = pb.x - Double(cx)
		var cols: [Int] = [cx]
		if frac < 0.34 { cols.append(cx - 1) } else if frac > 0.66 { cols.append(cx + 1) }
		let y0: Int = Int(floor(pb.top + 0.1))
		let y1: Int = Int(floor(pb.y + 0.05))
		for tx in cols {
			var y: Int = y0
			while y <= y1 {
				let t: Tile = world.tile(tx, y)
				if t == .ladder { return tx }
				// a mod's climbable block works the same way
				if t.isMod && ModRuntime.shared.climbTiles.contains(t.rawValue) { return tx }
				// a platform laid over the top of a ladder (a hatch) is climbed through and stepped onto
				if t == .platform && world.tile(tx, y + 1) == .ladder { return tx }
				y += 1
			}
		}
		return nil
	}

	func onLadder() -> Bool { return ladderColumn() != nil }

	/// Whether the player's body is in a mod's sticky block
	func inStickyBlock() -> Bool {
		let st: Set<UInt8> = ModRuntime.shared.stickyTiles
		if st.isEmpty { return false }
		let hw: Double = pb.w * 0.5
		let x0: Int = Int(floor(pb.x - hw + 0.02))
		let x1: Int = Int(floor(pb.x + hw - 0.02))
		let y0: Int = Int(floor(pb.top + 0.02))
		let y1: Int = Int(floor(pb.y - 0.02))
		if x1 < x0 || y1 < y0 { return false }
		for ty in y0...y1 {
			for tx in x0...x1 where st.contains(world.tile(tx, ty).rawValue) { return true }
		}
		return false
	}

	/// A ledge in front of the player whose top is at most about 2.5 blocks above the feet, with room
	/// to stand on it
	func ledgeWithinReach(_ dir: Int) -> Bool {
		let fx: Int = Int(floor(pb.x + Double(dir) * (pb.w * 0.5 + 0.15)))
		let feet: Int = Int(floor(pb.y - 0.05))
		var k: Int = 0
		while k <= 3 {
			let row: Int = feet - k
			if !world.solid(fx, row) && !world.solid(fx, row - 1) && world.solid(fx, row + 1) {
				return pb.y - Double(row + 1) <= 2.6
			}
			k += 1
		}
		return false
	}

	func checkHazards(_ dt: Double) {
		if mode == .creative || godMode { return }
		// spikes underfoot, cactus touched from the side (cactus is solid, so test a slightly wider box)
		if let t = world.boxHurts(pb.left + 0.05, pb.top + 0.1, pb.right - 0.05, pb.y - 0.02) ?? world.boxHurts(pb.left - 0.04, pb.top + 0.2, pb.right + 0.04, pb.y - 0.1) {
			if t == .spikes || t == .cactus || t.isMod {
				let dmg: Double = t.isMod ? (ModRuntime.shared.blockDef(t)?.power ?? 4) : (t == .spikes ? 6 : 3)
				var info = DamageInfo(amount: dmg, type: .hazard, source: .environment)
				info.originX = pb.x + Double(-facing)
				info.knock = 5
				_ = hurtPlayer(info)
			}
		}
		if world.tile(Int(floor(pb.x)), Int(floor(pb.y - 0.5))) == .campfire { playerBurn = max(playerBurn, 1.2) }
		if pb.inLava {
			let charm: Bool = wearing(.emberCharm)
			playerBurn = max(playerBurn, charm ? 1.0 : 2.5)
			lavaT += dt
			if lavaT > 0.35 {
				lavaT = 0
				var info = DamageInfo(amount: charm ? 2 : 5, type: .lava, source: .environment)
				info.originX = pb.x
				_ = hurtPlayer(info)
			}
		} else {
			lavaT = 0
		}
		updatePlayerBurn(dt)
		modLiquidEffects(dt)
	}

	/// Whether the player's head is under water (below the surface of a part-full cell too), and not in
	/// the dry air inside a vehicle
	func headUnderWater() -> Bool {
		let hy: Double = pb.y - pb.h * 0.92
		let hx: Int = Int(floor(pb.x))
		let hyI: Int = Int(floor(hy))
		let t: Tile = world.tile(hx, hyI)
		if !t.liquid || t == .lava || Liquids.hotTable[Int(t.rawValue)] { return false }
		if hy - Double(hyI) < 1.0 - world.liquidAmount(hx, hyI) { return false }
		if pb.ride != 0, let v = vehicleByID(pb.ride), v.dryAt(pb.rlx, pb.rly - pb.h * 0.92) { return false }
		return true
	}

	func updateSurvival(_ dt: Double, _ ix: Double) {
		if mode == .creative { return }
		// air
		let headY: Int = Int(floor(pb.y - pb.h * 0.92))
		// a Deepbreath Draught or a sealed suit keeps the air coming
		if headUnderWater() && effects.value(.breathing) <= 0 && !suitHas(.seal) {
			air -= dt * (wearing(.divingMask) ? 1.0 / 3.0 : 1.0)
			if air <= 0 {
				air = 0
				drownT += dt
				if drownT >= 1.0 {
					drownT = 0
					damagePlayer(2, from: pb.x, knock: 0, ignoreArmor: true)
				}
			}
		} else {
			air = min(10.0, air + dt * 5.0)
			drownT = 0
		}
		// hunger
		let rate: Double = (ix != 0 ? 0.030 : 0.016) * (pb.inWater ? 1.3 : 1.0)
		hunger = max(0, hunger - rate * ModRuntime.shared.rule(.hunger) * dt)
		if hunger <= 0 {
			starveT += dt
			if starveT >= 3.0 {
				starveT = 0
				if hp > 1 || mode == .hardcore { damagePlayer(1, from: pb.x, knock: 0, ignoreArmor: true) }
			}
		} else {
			starveT = 0
		}
		// a frozen body does not heal until it has warmed up
		let healRule: Double = ModRuntime.shared.rule(.healing)
		if hunger >= 14 && hp < maxHP && bodyCold < 0.9 && healRule > 0 {
			regenT += dt
			let period: Double = (hunger >= 18 ? 0.9 : 1.6) / healRule
			if regenT >= period {
				regenT = 0
				hp = min(maxHP, hp + 1)
				hunger = max(0, hunger - 0.12)
				bumpHUD()
			}
		} else {
			regenT = 0
		}
	}

	func damagePlayer(_ dmg: Double, from sx: Double, knock: Double = 6, ignoreArmor: Bool = false) {
		if dead || godMode || mode == .creative { return }
		if invuln > 0 && !ignoreArmor { return }
		let hurtRule: Double = ModRuntime.shared.rule(.hurt)
		if hurtRule <= 0 { return }
		var d: Double = dmg * hurtRule
		if !ignoreArmor { d *= 1.0 - armorShare(totalDefense) }
		d = max(1.0, d.rounded())
		hp -= d
		if remoteID != 0 { endRemote("Hurt: you let go of the remote.") }
		sfx(.hurt, 0.8)
		invuln = 0.55
		hurtT = 0.35
		if knock > 0 {
			let dirk: Double = pb.x >= sx ? 1.0 : -1.0
			pb.vx = dirk * knock
			pb.vy = -6.0
		}
		floatText("-" + String(Int(d)), pb.x, pb.y - pb.h - 0.3, 0xFF5050)
		addShake(0.2)
		bumpHUD()
		if hp <= 0 { die() }
	}

	/// The share of a blow that armour takes: 4% a point, at most 80% (never invincible)
	func armorShare(_ defense: Double) -> Double {
		return min(0.8, max(0, defense) * 0.04)
	}

	func heal(_ amount: Double) {
		hp = min(maxHP, hp + amount)
		bumpHUD()
	}

	func die() {
		if dead { return }
		dropBagOnDeath()
		dead = true
		hp = 0
		deathT = 0
		mounted = nil
		if let v = inVehicle { v.rider = false }
		inVehicle = nil
		if remoteID != 0 { endRemote() }
		spawnParticles(pb.x, pb.y - 1, 0xC03030, 24, 6.0, 0.9, 16)
		say(mode == .hardcore ? "You died. Your hardcore world is lost." : "You died!", 5.0)
		if mode == .hardcore { hardcoreOver = true }
		bumpHUD()
	}

	func respawn() {
		if mode == .hardcore && hardcoreOver { return }
		if world.dim != .overworld { travelTo(.overworld, arriveX: spawnX, arriveY: spawnY, silent: true) }
		dimReturn = nil
		dead = false
		hp = maxHP
		hunger = max(hunger, 14)
		air = 10
		pb.x = spawnX
		pb.y = spawnY
		pb.vx = 0
		pb.vy = 0
		pb.ride = 0
		invuln = 3.0
		fallPeak = 0
		world.loadAround(centerX: Int(spawnX), radius: 3)
		let sy: Int = world.surfaceY(Int(spawnX))
		pb.y = Double(sy)
		camX = pb.x
		camY = pb.y - 2
		say("Respawned.", 2.0)
		bumpHUD()
	}

	// MARK: camera, streaming, light

	/// Camera follow: a dead zone around the player, optional look-ahead in the direction of travel
	/// (eased so turning around does not jerk the view), and frame-rate independent exponential smoothing.
	func updateCamera(_ dt: Double) {
		let st: Settings = settings
		// Carried by a vehicle (driving it, or standing on it), the view is carried along with it, so
		// the smoothing below only ever has the player's own movement to follow. Without this the view
		// fell further behind the faster a vehicle went, and at a few hundred blocks a second lost it.
		// (driving by remote, the view goes with the vehicle, not the player)
		let rv: Vehicle? = remoteVehicle
		var carrier: Vehicle? = inVehicle ?? rv
		if carrier == nil && pb.ride != 0 { carrier = vehicleByID(pb.ride) }
		if let cv = carrier {
			let pv: (Double, Double) = rv != nil ? (cv.vx, cv.vy) : cv.pointVel(pb.x, pb.y)
			camX += pv.0 * dt
			camTX += pv.0 * dt
			camY += pv.1 * dt
			camTY += pv.1 * dt
		}
		// look ahead: further when driving fast, eased in and out
		var leadTarget: Double = 0
		if st.camLookAhead && !st.camDirect {
			if let v = carrier {
				leadTarget = clampD(v.vx * 0.35, -6.0, 6.0)
			} else if abs(pb.vx) > 1.0 {
				leadTarget = Double(facing) * 1.6
			}
		}
		camLead += (leadTarget - camLead) * min(1.0, dt * 2.5)
		let fx: Double = (rv?.px ?? pb.x) + camLead
		let fy: Double = rv != nil ? (rv?.py ?? pb.y) : pb.y - 1.6
		// the target only moves once the player leaves the dead zone around it
		let dz: Double = st.camDirect ? 0 : clampD(st.camDeadZone, 0, 4)
		if fx > camTX + dz { camTX = fx - dz } else if fx < camTX - dz { camTX = fx + dz }
		let dzy: Double = dz * 0.75
		if fy > camTY + dzy { camTY = fy - dzy } else if fy < camTY - dzy { camTY = fy + dzy }
		if abs(camTX - camX) > 40 || abs(camTY - camY) > 40 || !st.camSmoothOn {
			// teleports, respawns and "smoothing off" snap straight to the target
			camX = camTX
			camY = camTY
		} else {
			let rate: Double = st.camDirect ? 12.0 : 2.5 + clampD(st.camFollow, 0, 1) * 11.5
			let k: Double = 1.0 - exp(-rate * dt)
			camX += (camTX - camX) * k
			camY += (camTY - camY) * k
		}
		let halfW: Double = viewTilesW * 0.5
		let halfH: Double = viewTilesH * 0.5
		if !gen.infinite {
			if viewTilesW < Double(gen.width) { camX = clampD(camX, halfW, Double(gen.width) - halfW) }
		}
		let Hh: Double = Double(world.H)
		camY = clampD(camY, halfH - 14.0, Hh - halfH + 1.0)
	}

	func updateStreaming() {
		let need: Int = Int(ceil(viewTilesW * 0.5 / Double(chunkW))) + 2
		loadRadius = need
		var keep: Set<Int> = []
		for m in mobs where m.persistent || m.isBoss || m.tame {
			keep.insert(floorDiv(Int(floor(m.b.x)), chunkW))
		}
		for v in vehicles { keep.insert(floorDiv(Int(floor(v.b.x)), chunkW)) }
		keepWorkingLand(&keep)
		let cx: Int = Int(floor(camX))
		let n: Int = world.stream(centerX: cx, radius: loadRadius, hysteresis: 3, budget: 1, keep: keep)
		chunksLoadedLast = n
		// keep the player's own chunk always available
		let pc: Int = floorDiv(Int(floor(pb.x)), chunkW)
		if world.chunks[pc] == nil { world.loadChunk(pc) }
	}

	func heldLightLevel() -> Int {
		if let it = heldItem, case .custom(let k) = it, let r = ModRuntime.shared.item(k), r.def.light > 0 { return r.def.light }
		if let it = heldItem, case .block(let t) = it {
			let l: Int = t.light
			if l >= 9 { return l - 2 }
		}
		return 0
	}

	func updateLight(_ dt: Double) {
		lightTimer -= dt
		// dynamic lights
		var dyn: [(Int, Int, Int)] = []
		let pcx: Int = Int(floor(pb.x))
		let pcy: Int = Int(floor(pb.y - pb.h * 0.6))
		var hl: Int = heldLightLevel()
		hl = max(hl, wearing(.headlamp) ? 11 : 5)
		hl = max(hl, Int(effects.value(.glow)))
		if suitLit { hl = max(hl, 12) }
		dyn.append((pcx, pcy, hl))
		for m in mobs {
			var lv: Int = 0
			switch m.kind {
			case .emberSlime: lv = 9
			case .imp: lv = 8
			case .wraith: lv = 6
			case .cinderBat: lv = 6
			case .bearBoss, .rex: lv = m.isBoss ? 6 : 0
			case .sentinel: lv = 9
			case .warden: lv = 10
			case .custom: lv = clampI(ModRuntime.shared.mob(m.cslot)?.def.glow ?? 0, 0, 12)
			default: lv = 0
			}
			if m.burn > 0 { lv = max(lv, 6) }
			if lv > 0 { dyn.append((Int(floor(m.b.x)), Int(floor(m.b.y - m.b.h * 0.5)), lv)) }
		}
		for p in projectiles where p.mod >= 0 && p.mod < ModRuntime.shared.shots.count {
			let gl: Int = ModRuntime.shared.shots[p.mod].glow
			if gl > 0 { dyn.append((Int(floor(p.x)), Int(floor(p.y)), gl)) }
		}
		for p in projectiles where p.kind == .fireball || p.kind == .bomb {
			// fireballs glow; a bomb's lit fuse gives a small light
			dyn.append((Int(floor(p.x)), Int(floor(p.y)), p.kind == .fireball ? 10 : 5))
		}
		for f in flashes {
			let lv: Int = f.level
			if lv > 0 { dyn.append((Int(floor(f.x)), Int(floor(f.y)), lv)) }
		}
		for z in fireZones { dyn.append((Int(floor(z.x)), Int(floor(z.y - 0.6)), 11)) }
		for s in ships {
			dyn.append((Int(floor(s.x)) - 3, Int(floor(s.deckY(Double(WorldGen.sea)))) - 2, 10))
			dyn.append((Int(floor(s.x)) + 3, Int(floor(s.deckY(Double(WorldGen.sea)))) - 2, 10))
		}
		for v in vehicles where v.rider && v.engines > 0 && v.fuel > 0 {
			dyn.append((Int(floor(v.b.x + Double(v.dir) * (v.b.w * 0.5 + 1.0))), Int(floor(v.b.y - v.b.h * 0.5)), 10))
		}
		// lamps and torches built onto a vehicle light it up wherever it goes
		for v in vehicles where !v.blocks.isEmpty {
			for (cell, b) in v.blocks where b.light > 0 {
				let p: (Double, Double) = v.cellCenter(cell)
				dyn.append((Int(floor(p.0)), Int(floor(p.1)), b.light))
			}
		}
		// headlights throw a beam ahead of a driven vehicle
		for v in vehicles where v.rider && v.headlights > 0 {
			for (cell, t) in v.parts where t == .headlight {
				let d: Double = Double(v.dir)
				for (k, lv) in [(0.0, 10), (2.5, 14), (5.0, 13), (7.5, 11)] {
					let p: (Double, Double) = v.toWorld(Double(cell.dx) + 0.5 + d * k, Double(cell.dy) + 0.5)
					dyn.append((Int(floor(p.0)), Int(floor(p.1)), lv))
				}
			}
		}
		let nightVision: Bool = effects.value(.nightVision) > 0
		var key: Int = dyn.count &+ (nightVision ? 7919 : 0)
		for d in dyn { key = key &* 31 &+ d.0 &* 7 &+ d.1 &* 13 &+ d.2 }
		// window
		let vw: Int = Int(ceil(viewTilesW)) + 2
		let vh: Int = Int(ceil(viewTilesH)) + 2
		let vx0: Int = Int(floor(camX - viewTilesW * 0.5)) - 1
		let vy0: Int = Int(floor(camY - viewTilesH * 0.5)) - 1
		let covered: Bool = light.covers(vx0 - 3, vy0 - 3, vx0 + vw + 3, vy0 + vh + 3)
		// only edits that touch the light window matter (crops growing far away do not)
		var edited: Bool = false
		if world.editAny {
			let ex0: Int = light.ox - 1
			let ex1: Int = light.ox + light.w
			let ey0: Int = light.oy - 1
			let ey1: Int = light.oy + light.h
			if world.editX1 >= ex0 && world.editX0 <= ex1 && world.editY1 >= ey0 && world.editY0 <= ey1 {
				edited = true
			} else {
				world.editAny = false
			}
		}
		let layoutChanged: Bool = light.layoutUsed != world.layoutVersion
		let needsStatic: Bool = !light.valid || !covered || light.skyUsed != skyLevel || light.dimUsed != world.dim.rawValue || edited || layoutChanged
		let amb: Double = ambientLight()
		if !needsStatic {
			// only moving lights changed: cheap partial relight
			if light.dynUsed == key { return }
			let t0: Double = perfNow()
			light.applyDynamic(dyn)
			light.dynUsed = key
			light.buildPixels(&lightDark, &lightGlow, amb, 1.0 - dayFactor)
			lightRev &+= 1
			Perf.shared.lightDyn += 1
			Perf.shared.lightMs = Perf.smooth(Perf.shared.lightMs, perfNow() - t0)
			return
		}
		if lightTimer > 0 && light.valid && covered && light.dimUsed == world.dim.rawValue { return }
		let t0: Double = perfNow()
		lightTimer = 0.04
		let m: Int = 17
		var ox: Int = vx0 - m
		ox = floorDiv(ox, 4) * 4
		var oy: Int = vy0 - m
		oy = floorDiv(oy, 4) * 4
		var w: Int = (vx0 + vw + m) - ox + 4
		w = (w / 4 + 1) * 4
		var h: Int = (vy0 + vh + m) - oy + 4
		h = (h / 4 + 1) * 4
		light.compute(world, ox, oy, w, h, skyLevel, dyn)
		light.dynUsed = key
		light.buildPixels(&lightDark, &lightGlow, amb, 1.0 - dayFactor)
		lightRev &+= 1
		Perf.shared.lightMs = Perf.smooth(Perf.shared.lightMs, perfNow() - t0)
	}

	/// The least light anywhere: the dimension's own glow (a cavern dimension glows as brightly as its
	/// maker set its light, as it has no sky to light it), or more with an Owlsight Draught
	func ambientLight() -> Double {
		var amb: Double = fullBright ? 1.0 : (world.dim == .umbral ? 0.2 : (world.dim.isCustom ? 0.12 : 0.07))
		if !fullBright, let d = customDim, d.def.ceiling { amb = max(amb, 0.12 + 0.22 * clampD(d.def.light, 0, 1)) }
		if effects.value(.nightVision) > 0 { amb = max(amb, 0.5) }
		return amb
	}

	// MARK: random world ticks (crops, grass)

	func updateWorldTicks(_ dt: Double) {
		let n: Int = 7
		let px: Int = Int(floor(pb.x))
		let py: Int = Int(floor(pb.y))
		for _ in 0..<n {
			let x: Int = px + Int.random(in: -40...40)
			let y: Int = py + Int.random(in: -26...26)
			let t: Tile = world.tile(x, y)
			// rain falling on a crop (not snow) helps it along
			var grow: Double = 0.35
			if t.isPlant && weatherRain > 0.2 && !weatherSnow && y < world.rainTop(x) + 1 { grow = 0.35 + 0.3 * weatherRain }
			switch t {
			case .wheat1: if Double.random(in: 0...1) < grow { world.set(x, y, .wheat2) }
			case .wheat2: if Double.random(in: 0...1) < grow { world.set(x, y, .wheat3) }
			case .carrot1: if Double.random(in: 0...1) < grow { world.set(x, y, .carrot2) }
			case .carrot2: if Double.random(in: 0...1) < grow { world.set(x, y, .carrot3) }
			case .sapling: if Double.random(in: 0...1) < grow * 0.4 { growSapling(x, y) }
			case .dirt:
				if world.dim == .overworld && y < world.skyTop(x) + 1 && world.tile(x, y - 1) == .air {
					let a: Tile = world.tile(x - 1, y)
					let b: Tile = world.tile(x + 1, y)
					if a == .grass || b == .grass { if Double.random(in: 0...1) < 0.2 { world.set(x, y, .grass) } }
				}
			case .grass:
				if world.tile(x, y - 1).opaque && Double.random(in: 0...1) < 0.3 { world.set(x, y, .dirt) }
			default: break
			}
		}
		updateLeafDecay(dt)
		// lantern/torch/crop support is checked when neighbours change (see breakTile)
	}

	/// Open air or a wild plant a growing tree may take the place of (never a torch or anything built)
	func treeRoom(_ t: Tile) -> Bool {
		return t == .air || t == .tallGrass || t == .flowerR || t == .flowerY || t == .deadBush
	}

	/// A sapling grows into a tree that suits the land it stands in: a pine in snow and on mountains, a
	/// tall jungle tree, a flat-topped savanna tree, a low swamp tree, a birch or an oak elsewhere (in a
	/// custom dimension, a tree of its region's own log and leaves). It grows as tall as the room above
	/// it allows, and waits while there is not room for its smallest kind. True when it grew.
	@discardableResult
	func growSapling(_ x: Int, _ y: Int) -> Bool {
		if world.tile(x, y) != .sapling || !world.isSoil(world.tile(x, y + 1)) { return false }
		let r: Double = Double.random(in: 0..<1)
		var log: Tile = .log
		var leaves: Tile = .leaves
		// 0 oak, 1 birch, 2 pine, 3 jungle, 4 savanna, 5 swamp
		var shape: Int = 0
		if let d = customDim {
			let z: ModDimZoneRT = d.zones[d.zoneIndex(x)]
			if !z.designs.isEmpty { return growDesign(d, z, x, y) }
			log = z.log
			leaves = z.leaves
		} else {
			switch biomeAt(Double(x)) {
			case .tundra, .mountain: shape = 2; leaves = .pineLeaves
			case .jungle: shape = 3; log = .jungleLog; leaves = .jungleLeaves
			case .savanna: shape = 4
			case .swamp: shape = 5; leaves = .jungleLeaves
			default: if r < 0.3 { shape = 1; log = .birchLog; leaves = .birchLeaves }
			}
		}
		let wants: [Int] = [4 + Int(r * 4.0), 6 + Int(r * 4.0), 6 + Int(r * 5.0), 9 + Int(r * 6.0), 5 + Int(r * 3.0), 4 + Int(r * 2.0)]
		let least: [Int] = [4, 5, 6, 8, 5, 4]
		// free cells straight up from the sapling (its own cell counts): the trunk and two above it
		var room: Int = 1
		while room < wants[shape] + 2 && treeRoom(world.tile(x, y - room)) { room += 1 }
		let th: Int = min(wants[shape], room - 2)
		if th < least[shape] { return false }
		let gy: Int = y + 1
		for k in 1...th { world.set(x, gy - k, log) }
		func leaf(_ lx: Int, _ ly: Int) {
			if treeRoom(world.tile(lx, ly)) { world.set(lx, ly, leaves) }
		}
		let top: Int = gy - th
		switch shape {
		case 1:
			for dy in -4...0 {
				let w: Int = (dy == -4 || dy == 0) ? 1 : 2
				for dx in -w...w { leaf(x + dx, top + dy) }
			}
			leaf(x, top - 5)
		case 2:
			var layer: Int = 0
			while layer < th - 1 {
				let w: Int = min(3, 1 + layer / 2)
				for dx in -w...w { leaf(x + dx, top - 1 + layer) }
				layer += 1
			}
			leaf(x, top - 2)
		case 3:
			for dy in -3...1 {
				for dx in -4...4 where !(abs(dx) == 4 && abs(dy + 1) > 1) && abs(dx) + abs(dy + 1) <= 6 { leaf(x + dx, top + dy) }
			}
		case 4:
			for dx in -4...4 { leaf(x + dx, top) }
			for dx in -2...2 { leaf(x + dx, top - 1) }
		case 5:
			for dx in -3...3 {
				leaf(x + dx, top)
				if abs(dx) < 3 { leaf(x + dx, top - 1) }
			}
		default:
			for dy in -3...1 {
				for dx in -2...2 where !(abs(dx) == 2 && (dy == -3 || dy == 1)) { leaf(x + dx, top + dy) }
			}
		}
		spawnParticles(Double(x) + 0.5, Double(top) + 0.5, 0x56A83F, 8, 3.0, 0.6, 10)
		return true
	}

	/// A sapling in a region with tree designs grows into one of them that suits the ground under it,
	/// as tall as the room above allows (it waits while even its smallest won't fit). True when it grew.
	func growDesign(_ d: ModDimRT, _ z: ModDimZoneRT, _ x: Int, _ y: Int) -> Bool {
		let below: Tile = world.tile(x, y + 1)
		guard let tr = d.pickDesign(z, below, Double.random(in: 0..<1)) else { return false }
		let gy: Int = y + 1
		let seed: UInt64 = UInt64.random(in: 0...UInt64.max)
		let painted: Bool = tr.def.shape == .painted
		let least: Int = painted ? 1 : clampI(tr.def.minHeight, 1, 24)
		var h: Int = painted ? 1 : max(least, clampI(tr.def.maxHeight, 1, 24))
		while h >= least {
			let cells: [TreeCell] = TreeShapes.cells(tr.def, h, seed)
			// every cell of its trunk and branches has to be free (the sapling's own cell counts)
			var fits: Bool = !cells.isEmpty
			for c in cells where c.part != 3 {
				let t: Tile = world.tile(x + c.dx, gy - c.dy)
				let own: Bool = c.dx == 0 && c.dy == 1
				if !(own || treeRoom(t)) || gy - c.dy < 2 {
					fits = false
					break
				}
			}
			if fits {
				world.set(x, y, .air)
				var top: Int = y
				for c in cells {
					let cx: Int = x + c.dx
					let cy: Int = gy - c.dy
					if cy < 2 || !treeRoom(world.tile(cx, cy)) { continue }
					world.set(cx, cy, tr.tile(c.part))
					top = min(top, cy)
				}
				spawnParticles(Double(x) + 0.5, Double(top) + 0.5, 0x56A83F, 8, 3.0, 0.6, 10)
				return true
			}
			h -= 1
		}
		return false
	}
}

// ===== p14c_input =====

// MARK: - Pointer input, interaction, inventory operations, crafting

extension Game {
	// MARK: pointer (world coordinates in tiles)

	func pointerDown(_ wx: Double, _ wy: Double) {
		aimX = wx
		aimY = wy
		aimValid = true
		if capturing {
			if !showCapture { captureTap(wx, wy) }
			return
		}
		downTime = 0
		usePressedFlag = false
		touchActive = true
		// with a weapon out, a tap on a foe is an attack, even if a door or chest is behind it
		let fight: Bool = (heldItem?.isWeapon ?? false) && hostileAt(wx, wy)
		if !fight && isInteractive(wx, wy) {
			pendingInteract = true
			useHeld = false
		} else {
			pendingInteract = false
			useHeld = true
			useWasHeld = false
		}
		pointerStartX = wx
		pointerStartY = wy
	}

	func pointerMove(_ wx: Double, _ wy: Double) {
		aimX = wx
		aimY = wy
		aimValid = true
		if capturing { return }
		if pendingInteract {
			let dx: Double = wx - pointerStartX
			let dy: Double = wy - pointerStartY
			if dx * dx + dy * dy > 0.5 {
				pendingInteract = false
				useHeld = true
			}
		}
	}

	func pointerUp() {
		touchActive = false
		if capturing {
			useHeld = false
			pendingInteract = false
			return
		}
		if pendingInteract {
			if downTime < 0.3 { interact(aimX, aimY) }
			pendingInteract = false
		}
		// the action button may still be held: then it carries on (and aims for itself again)
		if actState.held { return }
		if useHeld { useReleasedFlag = true }
		useHeld = false
		useWasHeld = false
	}

	/// A wild animal (bear, elephant, wolf, grizzly, polar bear, tiger, scorpion): neutral to the player
	func isWildAnimal(_ k: MobKind) -> Bool {
		switch k {
		case .elephant, .bear, .wolf, .grizzly, .polarBear, .tiger, .scorpion: return true
		default: return false
		}
	}

	/// A wild hunter the player has hurt lately (it fights back for twelve seconds)
	func wildProvoked(_ m: Mob) -> Bool {
		return clock - m.lastHitByPlayer < 12.0
	}

	/// A creature that is out to hurt the player: monsters and enemies, and animals once angered
	func isThreat(_ m: Mob) -> Bool {
		if m.angry { return true }
		if isWildAnimal(m.kind) { return wildProvoked(m) }
		return m.def.hostile
	}

	/// a hostile (or angered) creature under or right next to a point
	func hostileAt(_ wx: Double, _ wy: Double) -> Bool {
		for m in mobsNear(wx - 4, wx + 4) where m.hp > 0 && !m.tame && isThreat(m) {
			if wx >= m.b.left - 0.4 && wx <= m.b.right + 0.4 && wy >= m.b.top - 0.4 && wy <= m.b.y + 0.4 { return true }
		}
		return false
	}

	func updatePointerTimers(_ dt: Double) {
		if pendingInteract {
			downTime += dt
			if downTime >= 0.3 {
				pendingInteract = false
				useHeld = true
				useWasHeld = false
			}
		}
	}

	func reachDistance() -> Double {
		if infiniteReach { return 60 }
		return isCreative ? 8.0 : 5.5
	}

	func inReach(_ x: Double, _ y: Double) -> Bool {
		let dx: Double = x - pb.x
		let dy: Double = y - (pb.y - pb.h * 0.6)
		let r: Double = reachDistance()
		return dx * dx + dy * dy <= r * r
	}

	// MARK: interactive targets

	func mobAtPoint(_ wx: Double, _ wy: Double, _ pad: Double) -> Mob? {
		var best: Mob? = nil
		var bd: Double = 1e9
		for m in mobs {
			if m.hp <= 0 { continue }
			let x0: Double = m.b.left - pad
			let x1: Double = m.b.right + pad
			let y0: Double = m.b.top - pad
			let y1: Double = m.b.y + pad
			if wx >= x0 && wx <= x1 && wy >= y0 && wy <= y1 {
				let d: Double = abs(wx - m.b.x) + abs(wy - m.b.cy)
				if d < bd { bd = d; best = m }
			}
		}
		return best
	}

	func vehicleAtPoint(_ wx: Double, _ wy: Double) -> (Vehicle, PartCell)? {
		for v in vehicles {
			if wx < v.b.left - 0.2 || wx > v.b.right + 0.2 || wy < v.b.top - 0.2 || wy > v.b.y + 0.2 { continue }
			// pick in the vehicle's own (rotated) grid
			let c: PartCell = v.cellAt(wx, wy)
			if v.parts[c] != nil { return (v, c) }
		}
		return nil
	}

	/// A vehicle cell with a back wall under a point (in its box)
	func vehicleWallAtPoint(_ wx: Double, _ wy: Double) -> (Vehicle, PartCell)? {
		for v in vehicles where !v.walls.isEmpty {
			if wx < v.b.left - 0.2 || wx > v.b.right + 0.2 || wy < v.b.top - 0.2 || wy > v.b.y + 0.2 { continue }
			let c: PartCell = v.cellAt(wx, wy)
			if v.walls[c] != nil { return (v, c) }
		}
		return nil
	}

	func shipChestAt(_ wx: Double, _ wy: Double) -> PirateShip? {
		for s in ships {
			if s.looted { continue }
			let dy: Double = s.deckY(Double(WorldGen.sea))
			if abs(wx - (s.x - 2.5)) < 1.2 && abs(wy - (dy - 0.6)) < 1.4 { return s }
		}
		return nil
	}

	func isInteractive(_ wx: Double, _ wy: Double) -> Bool {
		let tx: Int = Int(floor(wx))
		let ty: Int = Int(floor(wy))
		let t: Tile = world.tile(tx, ty)
		// with wire in hand every tap lays or cuts wire, even over a door or a lever
		if holdingWireSpool { return false }
		if case .gadget(.probe)? = heldItem { return t.isPower || world.wireAt(tx, ty) != 0 }
		if t.isPower { return true }
		if t.isMod {
			guard let b = ModRuntime.shared.blockDef(t) else { return true }
			if b.function != .none && b.function != .bounce && b.function != .trap { return true }
		}
		switch t {
		case .chest, .workbench, .furnace, .campfire, .portalOff, .doorClosed, .doorOpen, .anvil, .tinkerBench, .riftForge, .alchemyStill, .infuser, .exoStation: return true
		case .weatherStation, .dopplerStation, .stormSiren, .lightningRod, .windTurbine, .rainBarrel, .rainCistern, .weatherVane, .heater, .shutterClosed, .shutterOpen: return true
		case .chair, .sofa, .bedL, .bedR, .cabinet, .wardrobe, .liftButton: return true
		default: break
		}
		if liftAt(wx, wy) != nil { return true }
		if let m = mobAtPoint(wx, wy, 0.15) {
			if m.tame { return true }
		}
		if vehicleAtPoint(wx, wy) != nil {
			if let it = heldItem, case .part = it { return false }
			if let it = heldItem, case .gadget(let g) = it, g == .wrench { return false }
			return true
		}
		if shipChestAt(wx, wy) != nil { return true }
		return false
	}

	func interact(_ wx: Double, _ wy: Double) {
		let tx: Int = Int(floor(wx))
		let ty: Int = Int(floor(wy))
		if !inReach(wx, wy) && !(mobAtPoint(wx, wy, 0.2)?.tame ?? false) {
			say("Too far away.", 1.2)
			return
		}
		let t: Tile = world.tile(tx, ty)
		if case .gadget(.probe)? = heldItem {
			probeAt(wx, wy)
			return
		}
		if case .gadget(.wrench)? = heldItem, wrenchLift(wx, wy) { return }
		if t == .exoStation {
			openExo()
			return
		}
		if t.isPower && t != .windTurbine {
			usePowerDevice(tx, ty, t)
			return
		}
		if t.isMod && interactModBlock(tx, ty, t) { return }
		switch t {
		case .chest:
			if tryMimic(tx, ty) { return }
			let firstLook: Bool = world.chests[world.chestKey(tx, ty)] == nil
			sfx(.chestOpen, 0.7)
			spawnParticles(Double(tx) + 0.5, Double(ty) + 0.3, 0xC8A878, 5, 2.0, 0.4, 6)
			if firstLook && world.chestItems(tx, ty).contains(where: { MineLoot.isExceptional($0.item) }) {
				// a rare find: it should feel like one
				sfx(.rareLoot, 0.8)
				spawnParticles(Double(tx) + 0.5, Double(ty) + 0.2, 0xFFE070, 16, 3.5, 0.9, -3)
				addLightFlash(Double(tx) + 0.5, Double(ty) + 0.3, peak: 10, dur: 0.8, radius: 1.8, color: 0xFFD860)
				say("Something rare glints in this chest!", 2.5)
			}
			openChest = IntPair(x: tx, y: ty)
			showInventory = true
			bumpHUD()
			return
		case .workbench:
			craftStation = .bench
			showInventory = true
			bumpHUD()
			return
		case .furnace:
			craftStation = .furnace
			showInventory = true
			bumpHUD()
			return
		case .campfire:
			craftStation = .campfire
			showInventory = true
			bumpHUD()
			return
		case .anvil, .tinkerBench, .riftForge:
			craftStation = t == .anvil ? .anvil : (t == .tinkerBench ? .tinker : .forge)
			showInventory = true
			bumpHUD()
			return
		case .alchemyStill:
			craftStation = .still
			showInventory = true
			sfx(.splash, 0.3)
			bumpHUD()
			return
		case .infuser:
			openInfuser()
			return
		case .portalOff:
			tryOpenPortal(tx, ty)
			return
		case .doorClosed, .doorOpen:
			toggleDoor(tx, ty)
			return
		case .weatherStation, .dopplerStation, .stormSiren, .lightningRod, .windTurbine, .rainBarrel, .rainCistern, .weatherVane, .heater, .shutterClosed, .shutterOpen:
			useWeatherDevice(tx, ty, t)
			return
		case .chair, .sofa:
			sitOn(tx, ty)
			return
		case .bedL, .bedR:
			sleepIn(tx, ty)
			return
		case .cabinet, .wardrobe:
			openStorage(tx, ty)
			return
		case .liftButton:
			callLift(tx, ty)
			return
		default: break
		}
		if let l = liftAt(wx, wy) {
			rideLiftTap(l, wy)
			return
		}
		if let m = mobAtPoint(wx, wy, 0.2) {
			interactMob(m)
			return
		}
		if let (v, c) = vehicleAtPoint(wx, wy) {
			interactVehicle(v, c)
			return
		}
		if let s = shipChestAt(wx, wy) {
			lootShip(s)
			return
		}
	}

	func interactMob(_ m: Mob) {
		switch m.kind {
		case .rex:
			if m.tame { mountRex(m) }
		case .wolf, .cat:
			if m.tame {
				m.st = m.st == 7 ? 0 : 7
				say(m.st == 7 ? "Your pet will stay here." : "Your pet follows you.", 2.0)
			}
		default: break
		}
	}

	func tryOpenPortal(_ tx: Int, _ ty: Int) {
		let key: Item = .gadget(.portalKey)
		if !isCreative && inv.total(key) < 1 {
			say("The portal is sealed. It needs a Portal Key.", 3.0)
			return
		}
		if !isCreative { _ = inv.remove(key, 1) }
		// flood fill all dormant portal tiles
		var stack: [IntPair] = [IntPair(x: tx, y: ty)]
		var count: Int = 0
		while let p = stack.popLast() {
			if world.tile(p.x, p.y) != .portalOff { continue }
			world.set(p.x, p.y, .portalOn)
			count += 1
			if count > 80 { break }
			stack.append(IntPair(x: p.x + 1, y: p.y))
			stack.append(IntPair(x: p.x - 1, y: p.y))
			stack.append(IntPair(x: p.x, y: p.y + 1))
			stack.append(IntPair(x: p.x, y: p.y - 1))
		}
		portalOpened = true
		spawnParticles(Double(tx) + 0.5, Double(ty) + 0.5, 0xF0A848, 40, 7.0, 1.2, 0)
		addShake(0.5)
		say("The rift tears open! Walk into it to cross to the Umbral Realm.", 5.0)
		sfx(.portal, 1.0)
		bumpHUD()
	}

	func lootShip(_ s: PirateShip) {
		if !s.crew.isEmpty {
			var alive: Bool = false
			for id in s.crew { for m in mobs { if m.id == id && m.hp > 0 { alive = true } } }
			if alive {
				say("Defeat the crew first!", 2.0)
				return
			}
		}
		s.looted = true
		var rng = RNG(UInt64(truncatingIfNeeded: s.id) &* 7919 &+ gen.seed)
		giveItem(.mat(.goldBar), 3 + rng.int(6))
		giveItem(.ammo(.bullet), 8 + rng.int(14))
		giveItem(.mat(.gunpowder), 2 + rng.int(5))
		if rng.double() < 0.35 { giveItem(.gun(.pistol), 1) }
		if rng.double() < 0.5 { giveItem(.mat(.diamond), 1 + rng.int(3)) }
		giveItem(.food(.cookedFish), 2 + rng.int(4))
		say("You looted the pirate treasure!", 3.0)
		spawnParticles(s.x - 2.5, s.deckY(Double(WorldGen.sea)) - 1, 0xF5D142, 20, 5.0, 0.9, 12)
	}

	// MARK: inventory operations (used by the UI)

	func tapSlot(_ i: Int) {
		if let h = carry {
			// place carried stack
			if let s = inv.slots[i] {
				if s.item == h.item && h.item.maxStack > 1 {
					let room: Int = h.item.maxStack - s.count
					let put: Int = min(room, h.count)
					var ns: Stack = s
					ns.count += put
					inv.slots[i] = ns
					if h.count - put > 0 {
						var c: Stack = h
						c.count = h.count - put
						carry = c
					} else {
						carry = nil
					}
				} else {
					inv.slots[i] = h
					carry = s
				}
			} else {
				inv.slots[i] = h
				carry = nil
			}
		} else if let s = inv.slots[i] {
			carry = s
			inv.slots[i] = nil
		}
		bumpHUD()
	}

	func splitSlot(_ i: Int) {
		if carry != nil { return }
		if let s = inv.slots[i], s.count > 1 {
			let half: Int = s.count / 2
			var a: Stack = s
			a.count = s.count - half
			var b: Stack = s
			b.count = half
			inv.slots[i] = a
			carry = b
			bumpHUD()
		}
	}

	// MARK: drag and drop

	enum SlotRef: Hashable {
		case inv(Int)
		case armor(Int)
		case chest(Int)
		case drop
		/// creative mode: back to the creative menu
		case trash
	}

	func stackAt(_ r: SlotRef) -> Stack? {
		switch r {
		case .inv(let i): return i >= 0 && i < inv.slots.count ? inv.slots[i] : nil
		case .armor(let i): return i >= 0 && i < inv.armor.count ? inv.armor[i] : nil
		case .chest(let i):
			guard let p = openChest else { return nil }
			let items: [Stack] = world.chestItems(p.x, p.y)
			return i >= 0 && i < items.count ? items[i] : nil
		case .drop, .trash: return nil
		}
	}

	private func tapRef(_ r: SlotRef) {
		switch r {
		case .inv(let i): tapSlot(i)
		case .armor(let i): tapArmorSlot(i)
		case .chest(let i): if let p = openChest { chestTapSlot(p.x, p.y, i) }
		case .drop: dropCarried()
		case .trash: discardCarried()
		}
	}

	/// Drags the stack in `from` onto `to`: places, merges or swaps using the same rules as tapping, so
	/// armour only goes into its own slot and chests keep their limits. Anything that cannot land goes
	/// back where it came from (or into the bag).
	func dragStack(from: SlotRef, to: SlotRef?) {
		if carry != nil { returnCarried() }
		if stackAt(from) == nil { return }
		tapRef(from)
		guard carry != nil else { return }
		if let to = to, to != from {
			tapRef(to)
		}
		if carry != nil {
			// put the remainder (or the swapped stack) back into the slot the drag started from
			switch from {
			case .chest:
				if let p = openChest { chestTapSlot(p.x, p.y, Int.max) }
			default:
				if stackAt(from) == nil { tapRef(from) }
			}
		}
		if carry != nil { returnCarried() }
		bumpHUD()
	}

	func sortBag() {
		returnCarried()
		inv.sortBag()
		say("Bag sorted.", 1.2)
		bumpHUD()
	}

	/// Folds partial stacks together across the bag and hotbar
	func stackAll() {
		returnCarried()
		let n: Int = inv.mergeStacks()
		say(n > 0 ? "Stacks merged." : "Nothing to merge.", 1.2)
		bumpHUD()
	}

	/// Creative mode: the held stack goes back to the creative menu (it leaves the bag). In survival it
	/// is thrown away instead, as with DROP.
	func discardCarried() {
		if carry == nil { return }
		if !isCreative {
			dropCarried()
			return
		}
		carry = nil
		sfx(.tap, 0.5)
		bumpHUD()
	}

	/// Moves every bag stack (not the hotbar) whose item the open chest already holds into that chest
	func quickStack() {
		guard let p = openChest else { return }
		var items: [Stack] = world.chestItems(p.x, p.y)
		var moved: Int = 0
		for i in Inventory.hotbarCount..<inv.slots.count {
			guard var s = inv.slots[i] else { continue }
			if !items.contains(where: { $0.item == s.item }) { continue }
			// top up existing chest stacks first, then use free chest slots
			if s.item.maxStack > 1 {
				for k in 0..<items.count where items[k].item == s.item && items[k].extra == s.extra && items[k].inf == s.inf && items[k].count < s.item.maxStack && s.count > 0 {
					let put: Int = min(s.item.maxStack - items[k].count, s.count)
					items[k].count += put
					s.count -= put
					moved += put
				}
			}
			if s.count > 0 && items.count < 27 {
				items.append(s)
				moved += s.count
				s.count = 0
			}
			inv.slots[i] = s.count > 0 ? s : nil
		}
		world.setChestItems(p.x, p.y, items)
		say(moved > 0 ? "Stored \(moved) items in the chest." : "Nothing here matches the chest.", 1.5)
		bumpHUD()
	}

	func dropCarried() {
		if let c = carry {
			spawnDrop(c, pb.x + Double(facing) * 0.8, pb.y - 1.2, Double(facing) * 4.0, -4.0, heldBack: true)
			carry = nil
			bumpHUD()
		}
	}

	func returnCarried() {
		if let c = carry {
			let left: Int = inv.add(c.item, c.count, extra: c.extra, inf: c.inf)
			if left > 0 { spawnDrop(Stack(item: c.item, count: left, extra: c.extra, inf: c.inf), pb.x, pb.y - 1.0, 2.0, -3.0) }
			carry = nil
			bumpHUD()
		}
	}

	/// Whether an item may go into armour slot `i`: armour into its own slot, gear into either gear slot
	func fitsArmorSlot(_ it: Item, _ i: Int) -> Bool {
		switch it {
		case .armor(let slot, _): return slot.rawValue == i && !(suit.worn && i < 3)
		case .gear: return i >= Inventory.firstGearSlot && i < inv.armor.count
		case .custom(let k):
			guard let r = ModRuntime.shared.item(k), r.def.kind == .armor else { return false }
			return r.def.slot == i && !(suit.worn && i < 3)
		default: return false
		}
	}

	func tapArmorSlot(_ i: Int) {
		if i < 0 || i >= inv.armor.count { return }
		if let h = carry {
			if fitsArmorSlot(h.item, i) {
				let old: Stack? = inv.armor[i]
				inv.armor[i] = h
				carry = old
			}
		} else if let s = inv.armor[i] {
			carry = s
			inv.armor[i] = nil
		}
		bumpHUD()
	}

	func quickEquip(_ i: Int) {
		guard let s = inv.slots[i] else { return }
		var target: Int = -1
		switch s.item {
		case .armor(let slot, _): target = slot.rawValue
		case .gear(let g):
			// the same piece already worn is swapped out; otherwise the first free gear slot, else the first
			target = Inventory.firstGearSlot
			var free: Int = -1
			for k in Inventory.firstGearSlot..<inv.armor.count {
				if let w = inv.armor[k], case .gear(let x) = w.item, x == g { free = k; break }
				if inv.armor[k] == nil && free < 0 { free = k }
			}
			if free >= 0 { target = free }
		case .custom(let k):
			guard let r = ModRuntime.shared.item(k), r.def.kind == .armor else { return }
			target = clampI(r.def.slot, 0, 2)
		default: return
		}
		if target < 0 || target >= inv.armor.count { return }
		let old: Stack? = inv.armor[target]
		inv.armor[target] = s
		inv.slots[i] = old
		bumpHUD()
	}

	func wearing(_ g: Gear) -> Bool { return inv.wearing(g) }

	// chest transfer
	func chestTapSlot(_ cx: Int, _ cy: Int, _ idx: Int) {
		var items: [Stack] = world.chestItems(cx, cy)
		if let h = carry {
			if idx < items.count {
				let s: Stack = items[idx]
				if s.item == h.item && h.item.maxStack > 1 {
					var ns: Stack = s
					let put: Int = min(h.item.maxStack - s.count, h.count)
					ns.count += put
					items[idx] = ns
					if h.count - put > 0 { var c: Stack = h; c.count = h.count - put; carry = c } else { carry = nil }
				} else {
					items[idx] = h
					carry = s
				}
			} else if items.count < 27 {
				items.append(h)
				carry = nil
			}
		} else if idx < items.count {
			carry = items[idx]
			items.remove(at: idx)
		}
		world.setChestItems(cx, cy, items)
		bumpHUD()
	}

	func chestQuickMove(_ cx: Int, _ cy: Int, _ idx: Int) {
		var items: [Stack] = world.chestItems(cx, cy)
		if idx >= items.count { return }
		let s: Stack = items[idx]
		let left: Int = inv.add(s.item, s.count, extra: s.extra, inf: s.inf)
		if left == 0 { items.remove(at: idx) } else { items[idx].count = left }
		world.setChestItems(cx, cy, items)
		bumpHUD()
	}

	func chestStore(_ cx: Int, _ cy: Int, _ slotIndex: Int) {
		guard let s = inv.slots[slotIndex] else { return }
		var items: [Stack] = world.chestItems(cx, cy)
		if items.count >= 27 { say("Chest is full.", 1.5); return }
		items.append(s)
		inv.slots[slotIndex] = nil
		world.setChestItems(cx, cy, items)
		bumpHUD()
	}

	// MARK: crafting

	func stationAvailable(_ s: Station) -> Bool {
		if s == .hand { return true }
		if isCreative { return true }
		let px: Int = Int(floor(pb.x))
		let py: Int = Int(floor(pb.y - 1))
		for dy in -4...3 {
			for dx in -5...5 {
				let t: Tile = world.tile(px + dx, py + dy)
				// a mod block that works as this station
				if t.isMod, let b = ModRuntime.shared.blockDef(t), b.function == .station, b.station == s.rawValue { return true }
				switch s {
				case .bench: if t == .workbench { return true }
				case .furnace: if t == .furnace { return true }
				case .campfire: if t == .furnace || t == .campfire { return true }
				case .anvil: if t == .anvil { return true }
				case .tinker: if t == .tinkerBench { return true }
				case .forge: if t == .riftForge { return true }
				case .still: if t == .alchemyStill { return true }
				case .infuser: if t == .infuser { return true }
				case .assembly: if t == .exoStation { return true }
				case .hand: return true
				}
			}
		}
		return false
	}

	func canCraft(_ r: Recipe) -> Bool {
		if !recipeStationOK(r) { return false }
		if !inv.canAfford(r.cost) { return false }
		return inv.canFit(r.out, r.outCount)
	}

	func craft(_ r: Recipe) {
		if !canCraft(r) {
			if !recipeStationOK(r) { say("Needs a " + recipeStationName(r) + " nearby.", 2.0) }
			return
		}
		for c in r.cost { _ = inv.remove(c.item, c.n) }
		if !journal.crafted.contains(r.out.name) { journal.crafted.append(r.out.name) }
		sfx(.craft, 0.6)
		// a new storm rod comes charged; firearms and crossbows still need loading
		let ex: Int = r.out == .gun(.stormRod) ? GunType.stormRod.magazine : 0
		let left: Int = inv.add(r.out, r.outCount, extra: ex)
		if left > 0 { spawnDrop(Stack(item: r.out, count: left, extra: ex), pb.x, pb.y - 1, 2, -3) }
		floatText("+" + String(r.outCount) + " " + r.out.name, pb.x, pb.y - 2.2, 0xFFE070)
		bumpHUD()
	}

	// MARK: creative palette

	/// Everything the creative palette offers: the game's items, then those of the world's mods
	func creativeItems() -> [Item] {
		return allGameItems() + ModRuntime.shared.paletteItems()
	}

	func creativeGive(_ it: Item) {
		let n: Int = it.maxStack > 1 ? it.maxStack : 1
		giveItem(it, n, extra: gunLoad(it))
		bumpHUD()
	}

	func gunLoad(_ it: Item) -> Int {
		if case .gun(let g) = it { return g.magazine }
		if case .custom(let k) = it, let r = ModRuntime.shared.item(k), r.def.kind == .gun { return r.def.magazine }
		return 0
	}
}

/// Every item of the game itself (no mod content), in palette order
func allGameItems() -> [Item] {
	var out: [Item] = []
	for t in Tile.allCases {
		if t.isMod { continue }
		switch t {
		case .bedR, .stairWoodL, .stairStoneL, .stairBrickL: continue
		case .air, .water, .lava, .bedrock, .portalFrame, .portalOff, .portalOn, .wheat1, .wheat2, .carrot1, .carrot2, .doorOpen,
			 .logBlock, .jungleLogBlock, .palmLogBlock, .birchLogBlock, .shutterOpen, .lampOn, .gateOpen: continue
		default: out.append(.block(t))
		}
	}
	for tier in Tier.allCases {
		for k in ToolType.allCases { out.append(.tool(k, tier)) }
		out.append(.sword(tier))
		out.append(.spear(tier))
		out.append(.hammer(tier))
		if tier != .wood { out.append(.knife(tier)) }
		for s in ArmorSlot.allCases { out.append(.armor(s, tier)) }
	}
	for g in Gear.allCases { out.append(.gear(g)) }
	out.append(.bow)
	out.append(.sling)
	for c in ClubKind.allCases { out.append(.club(c)) }
	for r in Relic.allCases { out.append(.relic(r)) }
	for gt in GunType.allCases { out.append(.gun(gt)) }
	for a in AmmoType.allCases { out.append(.ammo(a)) }
	for g in Gadget.allCases { out.append(.gadget(g)) }
	for k in wallKinds { out.append(.wall(k)) }
	for p in PartType.allCases where p != .block { out.append(.part(p)) }
	for f in Food.allCases { out.append(.food(f)) }
	for m in Mat.allCases { out.append(.mat(m)) }
	out.append(contentsOf: featureItems())
	return out
}

// ===== u06_root =====

// MARK: - Keyboard (hardware keyboards on iPad)

struct KeyInput: ViewModifier {
	let game: Game
	@FocusState var focused: Bool

	func body(content: Content) -> some View {
		if #available(iOS 17.0, macOS 14.0, *) {
			content
				.focusable()
				.focused($focused)
				.focusEffectDisabled()
				.onAppear { focused = true }
				.onKeyPress(phases: [.down, .up]) { press in handle(press) }
		} else {
			content
		}
	}

	@available(iOS 17.0, macOS 14.0, *)
	func handle(_ press: KeyPress) -> KeyPress.Result {
		let isDown: Bool = press.phase != .up
		if press.key == .leftArrow { game.keyL = isDown; return .handled }
		if press.key == .rightArrow { game.keyR = isDown; return .handled }
		if press.key == .upArrow || press.key == .space { game.jumpHeld = isDown; return .handled }
		if press.key == .downArrow { game.downHeld = isDown; return .handled }
		if press.key == .escape {
			if isDown { game.paused.toggle() }
			return .handled
		}
		if press.key == .tab {
			if isDown { game.showDebug.toggle() }
			return .handled
		}
		let c: String = press.characters.lowercased()
		switch c {
		case "a": game.keyL = isDown
		case "d": game.keyR = isDown
		case "w": game.jumpHeld = isDown
		case "s": game.downHeld = isDown
		case "f": if isDown { actState.held = true } else { actState.stickReleased() }
		case "e":
			if isDown {
				if game.showInventory {
					game.returnCarried()
					game.openChest = nil
					game.craftStation = .hand
					game.showInventory = false
				} else {
					game.showInventory = true
				}
			}
		case "m": if isDown && (game.gotMap || game.inv.total(.gadget(.treasureMap)) > 0) { game.showMap.toggle() }
		case "j": if isDown { game.showJournal.toggle() }
		case "r": if isDown { game.startReload() }
		case "q": if isDown { game.cycleWeapon() }
		case "x": if isDown { game.dismount() }
		case "=", "+": if isDown { game.tilePx = clampI(game.tilePx + 8, 16, 56); game.bumpHUD() }
		case "-": if isDown { game.tilePx = clampI(game.tilePx - 8, 16, 56); game.bumpHUD() }
		case "1", "2", "3", "4", "5", "6", "7", "8", "9":
			if isDown, let n = Int(c) { game.setSel(n - 1) }
		case "0":
			if isDown { game.setSel(9) }
		default:
			return .ignored
		}
		return .handled
	}
}

// MARK: - Game screen

final class LoopClock: @unchecked Sendable {
	var last: Double = 0
	var skip: Bool = false
	var pending: Double = 0
	var fpsN: Int = 0
}

/// The world picture. It only redraws when the game steps (it watches the frame ticker, not the whole game).
struct WorldLayer: View {
	let game: Game
	@ObservedObject var ticker: FrameTicker
	var body: some View {
		Canvas(opaque: true) { ctx, size in
			WorldLayer.render(&ctx, size, game)
		}
	}

	static func render(_ ctx: inout GraphicsContext, _ size: CGSize, _ g: Game) {
		g.viewW = Double(size.width)
		g.viewH = Double(size.height)
		WorldRenderer.draw(&ctx, size, g)
	}
}

struct GameView: View {
	@ObservedObject var game: Game
	var quit: () -> Void
	/// swaps in a fresh world (the Mod Test's reset)
	var restart: ((Game) -> Void)? = nil
	@State var dragging: Bool = false
	@State var clock: LoopClock = LoopClock()
	let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

	var body: some View {
		ZStack {
			worldLayer
			if !game.showInventory && !game.showMap && !game.showJournal && !game.showWeather && !game.showPower && !game.showCapture && !game.showModTest && !game.showInfuse && !game.showExo && !game.showJoint && !game.showRadio && !game.dead {
				HUDView(game: game, hud: game.hud)
			}
			if game.showInfuse {
				Color.black.opacity(0.45).ignoresSafeArea()
				GeometryReader { geo in
					InfusionPanel(game: game, hud: game.hud)
						.scaleEffect(min(1.0, min(geo.size.width / 960.0, geo.size.height / 640.0)))
						.frame(width: geo.size.width, height: geo.size.height)
				}
			}
			if game.showExo {
				Color.black.opacity(0.45).ignoresSafeArea()
				// no scroll view (it would fight with dragging): it scales to fit instead
				GeometryReader { geo in
					ExoAssemblyPanel(game: game, hud: game.hud)
						.scaleEffect(min(1.0, min(geo.size.width / 1010.0, geo.size.height / 560.0)))
						.frame(width: geo.size.width, height: geo.size.height)
				}
			}
			if game.showModTest {
				Color.black.opacity(0.45).ignoresSafeArea()
				ModTestPanel(game: game, hud: game.hud, reset: { resetTest() }, exit: quit)
			}
			if game.showJoint {
				Color.black.opacity(0.45).ignoresSafeArea()
				JointPanel(game: game, hud: game.hud)
			}
			if game.showRadio {
				Color.black.opacity(0.45).ignoresSafeArea()
				ReceiverPanel(game: game, hud: game.hud)
			}
			if game.capturing && !game.showCapture && !game.paused { CaptureBar(game: game, hud: game.hud) }
			if game.showCapture {
				Color.black.opacity(0.45).ignoresSafeArea()
				CapturePanel(game: game)
			}
			if game.showWeather {
				Color.black.opacity(0.4).ignoresSafeArea()
				ScrollView {
					WeatherPanel(game: game, hud: game.hud)
				}
			}
			if game.showPower {
				Color.black.opacity(0.4).ignoresSafeArea()
				ScrollView {
					PowerPanel(game: game, hud: game.hud)
				}
			}
			if game.showInventory {
				Color.black.opacity(0.35).ignoresSafeArea()
				// no scroll view around the panel (it would fight with dragging); it scales to fit instead
				GeometryReader { geo in
					InventoryPanel(game: game, hud: game.hud)
						.scaleEffect(min(1.0, min(geo.size.width / 1000.0, geo.size.height / 600.0)))
						.frame(width: geo.size.width, height: geo.size.height)
				}
			}
			if game.showMap {
				Color.black.opacity(0.45).ignoresSafeArea()
				ScrollView {
					MapPanel(game: game, hud: game.hud)
				}
			}
			if game.showJournal {
				Color.black.opacity(0.45).ignoresSafeArea()
				JournalPanel(game: game, hud: game.hud)
			}
			if game.showDebug && !game.showInventory && !game.showMap {
				HStack {
					Spacer()
					DebugPanel(game: game, hud: game.hud)
						.frame(width: 300)
						.padding(.top, 54)
						.padding(.bottom, 8)
						.padding(.trailing, 8)
				}
			}
			if game.paused { PauseView(game: game, hud: game.hud, quit: quit) }
			if game.dead { DeathView(game: game, hud: game.hud, quit: quit) }
		}
		.background(Color.black)
		.onReceive(timer) { _ in step() }
		.onAppear { Sound.shared.start() }
		.modifier(KeyInput(game: game))
	}

	/// A fresh test world for the mod being tested (read again from the store)
	func resetTest() {
		guard let p = ModStore.pack(game.testMod), let r = restart else { return }
		let ng: Game = ModTest.makeWorld(p, settings: game.settings)
		ng.tilePx = game.tilePx
		ng.say("The test world starts again.", 2.5)
		r(ng)
	}

	var worldLayer: some View {
		WorldLayer(game: game, ticker: game.ticker)
			.ignoresSafeArea()
			.contentShape(Rectangle())
			.gesture(worldGesture)
	}

	var worldGesture: some Gesture {
		DragGesture(minimumDistance: 0)
			.onChanged { v in touchMoved(v.location) }
			.onEnded { _ in touchEnded() }
	}

	func touchMoved(_ p: CGPoint) {
		let w: (Double, Double) = toWorld(p)
		if !dragging {
			dragging = true
			game.pointerDown(w.0, w.1)
		} else {
			game.pointerMove(w.0, w.1)
		}
	}

	func touchEnded() {
		dragging = false
		game.pointerUp()
	}

	func toWorld(_ p: CGPoint) -> (Double, Double) {
		let tp: Double = Double(game.tilePx)
		let wT: Double = game.viewW / tp
		let hT: Double = game.viewH / tp
		let left: Double = floor((game.camX - wT * 0.5) * 8.0) / 8.0
		let top: Double = floor((game.camY - hT * 0.5) * 8.0) / 8.0
		let px: Double = Double(p.x)
		let py: Double = Double(p.y)
		let wx: Double = left + px / tp
		let wy: Double = top + py / tp
		return (wx, wy)
	}

	/// One game step. Runs from a 60 Hz timer; in 30 fps mode every second tick is merged into the next.
	func step() {
		let now: Double = Date().timeIntervalSinceReferenceDate
		var dt: Double = now - clock.last
		if clock.last == 0 || dt > 0.1 { dt = 1.0 / 60.0 }
		clock.last = now
		game.updateInputGate()
		if game.paused { return }
		if !game.settings.fps60 {
			clock.skip.toggle()
			if clock.skip {
				clock.pending += dt
				return
			}
			dt += clock.pending
			clock.pending = 0
		}
		game.applyActButton()
		game.tick(dt)
		game.ticker.frame &+= 1
	}
}

// MARK: - Root

/// Saves when the app goes to the background (uses the iOS 17 onChange form when available)
struct PhaseWatcher: ViewModifier {
	let phase: ScenePhase
	let changed: (ScenePhase) -> Void

	func body(content: Content) -> some View {
		if #available(iOS 17.0, macOS 14.0, *) {
			content.onChange(of: phase) { _, newPhase in changed(newPhase) }
		} else {
			content.onChange(of: phase) { newPhase in changed(newPhase) }
		}
	}
}

struct RootView: View {
	@State var game: Game? = nil
	@State var settings: Settings = SettingsStore.load()
	/// back to the Mod Creator after a test world
	@State var reopenMods: Bool = false
	@Environment(\.scenePhase) var scenePhase

	var body: some View {
		ZStack {
			if let g = game {
				GameView(game: g, quit: { leave() }, restart: { ng in game = ng })
			} else {
				MenuView(settings: $settings, openMods: reopenMods) { g in
					game = g
				}
			}
		}
		.preferredColorScheme(.dark)
		.modifier(PhaseWatcher(phase: scenePhase, changed: phaseChanged))
	}

	func phaseChanged(_ phase: ScenePhase) {
		if phase != .active, let g = game {
			_ = g.saveNow()
			var s: Settings = g.settings
			s.tilePx = g.tilePx
			SettingsStore.save(s)
		}
	}

	func leave() {
		if let g = game {
			_ = g.saveNow()
			// everything changed in game (toggles, camera, zoom) carries back to the menu and is persisted
			settings = g.settings
			settings.tilePx = g.tilePx
			SettingsStore.save(settings)
			if g.mode == .hardcore && g.hardcoreOver { SaveStore.delete(g.slot) }
			reopenMods = !g.testMod.isEmpty
		}
		actState.stickReleased()
		// the weather and engine loops are only kept up by the world's frames: stop them with it
		Sound.shared.silenceLoops()
		game = nil
		ModRuntime.deactivate()
	}
}

@main
struct PixelRealmApp: App {
	var body: some Scene {
		WindowGroup {
			RootView()
		}
	}
}

// ===== u09_modplus =====

// MARK: - Mod Creator+: changing game content (screens)

/// The game's own blocks, items or creatures to pick from (for a change, or to start from)
struct GamePickerView: View {
	let kind: ModOverrideKind
	var title: String = "PICK FROM THE GAME"
	var pick: (Int, Item?) -> Void
	var cancel: () -> Void
	@State var filter: String = ""

	var body: some View {
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 92), spacing: 6)]
		return VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text(verbatim: title).font(.pixel(15)).foregroundColor(ModUI.gold)
				Spacer()
				SmallButton(title: "CANCEL", color: ModUI.red) { cancel() }
			}
			ModTextField(label: "Search", text: $filter, placeholder: "name")
			LazyVGrid(columns: cols, spacing: 6) {
				switch kind {
				case .block:
					ForEach(tiles, id: \.self) { t in
						cell(pixImage(tileBuf(t)), t.name) { pick(Int(t.rawValue), nil) }
					}
				case .item:
					ForEach(0..<items.count, id: \.self) { i in
						cell(Art.shared.icon(items[i]), items[i].name) { pick(0, items[i]) }
					}
				case .creature:
					ForEach(mobs, id: \.self) { k in
						cell(mobIcon(k), mobDef(k).name) { pick(k.rawValue, nil) }
					}
				}
			}
		}
		.padding(10)
		.background(PixelBox(color: ModUI.panel))
	}

	func match(_ name: String) -> Bool {
		let f: String = filter.trimmingCharacters(in: .whitespaces).lowercased()
		return f.isEmpty || name.lowercased().contains(f)
	}
	var tiles: [Tile] { return ModOverrideCheck.tiles().filter { match($0.name) } }
	var items: [Item] { return ModOverrideCheck.items().filter { match($0.name) } }
	var mobs: [MobKind] { return ModOverrideCheck.mobs().filter { match(mobDef($0).name) } }

	func mobIcon(_ k: MobKind) -> Image {
		let s: SpriteSet = Art.shared.creaturePreview(k)
		return s.frame(0, left: false, hurt: false)
	}

	func cell(_ img: Image, _ name: String, _ action: @escaping () -> Void) -> some View {
		Button(action: action) {
			VStack(spacing: 3) {
				img.resizable().interpolation(.none).frame(width: 40, height: 40)
				Text(verbatim: name).font(.pixel(9, .semibold)).foregroundColor(Color.white).lineLimit(2).multilineTextAlignment(.center)
			}
			.frame(maxWidth: .infinity, minHeight: 76)
			.background(ModUI.card)
		}
		.buttonStyle(.plain)
	}
}

/// The GAME CONTENT tab: every change this mod makes to the game's own content
struct GameContentList: View {
	@ObservedObject var s: ModSession
	var open: (String) -> Void
	@State var picking: ModOverrideKind? = nil
	@State var showSky: Bool = false
	@State var skyPick: Int = 0

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Change the game's own blocks, items and creatures: only the numbers you set change, the originals are kept, and switching a change off (or the whole mod) puts the game back as it was.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			skyPart
			if let k = picking {
				GamePickerView(kind: k, title: joinText("CHANGE A ", k.name.uppercased()), pick: { raw, it in add(k, raw, it) }, cancel: { picking = nil })
			} else {
				HStack(spacing: 6) {
					PixelButton(title: "+ BLOCK", color: ModUI.accent) { picking = .block }
					PixelButton(title: "+ ITEM", color: ModUI.accent) { picking = .item }
					PixelButton(title: "+ CREATURE", color: ModUI.accent) { picking = .creature }
				}
			}
			if s.mod.overrides.isEmpty && picking == nil {
				Text("No changes to game content yet.").font(.pixel(12)).foregroundColor(ModUI.dim)
			}
			ForEach(s.mod.overrides) { o in row(o) }
		}
	}

	/// The Overworld's sun and moon as this mod draws them
	var skyPart: some View {
		let shown: Bool = showSky
		let pick: Int = clampI(skyPick, 0, 1)
		let sun: String = s.mod.skySun == nil ? "the game's" : "its own"
		let moon: String = s.mod.skyMoon == nil ? "the game's" : "its own"
		let line: String = joinText("The Overworld's sky: ", sun, " sun, ", moon, " moon")
		return VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				Text(verbatim: line).font(.pixel(12, .bold)).foregroundColor(Color.white)
				Spacer(minLength: 0)
				SmallButton(title: shown ? "CLOSE" : "SUN AND MOON...", color: ModUI.blue) { self.showSky.toggle() }
			}
			if shown {
				ChoiceRows(options: DimensionEditorView.bodyNames, selected: $skyPick, columns: 2)
				if pick == 0 {
					SkyBodyEditor(sky: s.modBind(\.skySun), moon: false)
				} else {
					SkyBodyEditor(sky: s.modBind(\.skyMoon), moon: true, skyTop: 0x060A1E, skyBottom: 0x18223E)
				}
			}
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	func add(_ k: ModOverrideKind, _ raw: Int, _ it: Item?) {
		var o = ModOverride()
		o.id = s.mod.freshID("g")
		o.kind = k
		if k == .block { o.tile = raw }
		if k == .item { o.item = it }
		if k == .creature { o.mob = raw }
		// one change per thing: open the one there is
		if let same = s.mod.overrides.first(where: { $0.kind == k && (k == .block ? $0.tile == raw : (k == .item ? $0.item == it : $0.mob == raw)) }) {
			picking = nil
			open(same.id)
			return
		}
		s.mod.overrides.append(o)
		s.touch()
		picking = nil
		open(o.id)
	}

	func row(_ o: ModOverride) -> some View {
		let on: Binding<Bool> = s.bind(\.overrides, o.id, \.enabled, true)
		return HStack(spacing: 8) {
			overrideIcon(o).resizable().interpolation(.none).frame(width: 38, height: 38).background(Color.black.opacity(0.4))
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: o.targetName).font(.pixel(13)).foregroundColor(Color.white)
				Text(verbatim: joinText(o.kind.name, " · ", String(o.changedCount), o.changedCount == 1 ? " change" : " changes")).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer()
			SmallButton(title: o.enabled ? "ON" : "OFF", color: o.enabled ? ModUI.accent : Color(ui: 0x555555)) { on.wrappedValue.toggle() }
			SmallButton(title: "EDIT", color: ModUI.blue) { open(o.id) }
			SmallButton(title: "✕", color: ModUI.red) {
				s.mod.overrides.removeAll { $0.id == o.id }
				s.touch()
			}
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}
}

func overrideIcon(_ o: ModOverride) -> Image {
	switch o.kind {
	case .block: return pixImage(tileBuf(Tile(rawValue: UInt8(clampI(o.tile, 0, 255))) ?? .stone))
	case .item: return Art.shared.icon(o.item ?? .mat(.stick))
	case .creature: return Art.shared.creaturePreview(MobKind(rawValue: o.mob) ?? .zombie).frame(0, left: false, hurt: false)
	}
}

/// One number of a change: the game's value, a switch to change it, the new value, and RESTORE
struct OverrideField: View {
	let label: String
	let original: Double
	@Binding var value: Double?
	let range: ClosedRange<Double>
	var step: Double = 0
	var format: String = "%.1f"

	var body: some View {
		let changed: Bool = value != nil
		let bind: Binding<Double> = Binding<Double>(get: { value ?? original }, set: { value = $0 })
		return VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text(verbatim: label).font(.pixel(12)).foregroundColor(Color.white)
				Spacer()
				Text(verbatim: joinText("game: ", String(format: format, original))).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
				if changed {
					SmallButton(title: "RESTORE", color: Color(ui: 0x6A5A3A)) { value = nil }
				} else {
					SmallButton(title: "CHANGE", color: ModUI.blue) { value = original }
				}
			}
			if changed {
				StatSlider(label: "New value", value: bind, range: range, step: step, format: format)
			}
		}
		.padding(6)
		.background(Color.black.opacity(changed ? 0.3 : 0.15))
	}
}

/// A game creature's own sprite, repainted by a mod: its frames copied from the game to paint over (the
/// game then draws them in place of its own, timed the same), put back to the game's, or saved as a new
/// custom creature that starts from it
struct CreatureSpriteEditor: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var frame: Int = 0
	@State var note: String = ""

	var override: ModOverride { return s.mod.overrides.first { $0.id == id } ?? ModOverride() }
	var kind: MobKind { return MobKind(rawValue: override.mob) ?? .zombie }

	var body: some View {
		let fr: [ModPixels] = override.frames ?? []
		let help: String = fr.isEmpty ? "Paint over the game's own sprite: every frame, pixel by pixel." : "The game draws these frames instead of its own (standing, walking, then the rest, in the game's order)."
		return ModSection(title: "ITS SPRITE", help: help) {
			if fr.isEmpty { startRow } else { editor(fr) }
			if !note.isEmpty { Text(verbatim: note).font(.pixel(11, .semibold)).foregroundColor(ModUI.gold) }
		}
	}

	var startRow: some View {
		let bufs: [PixelBuf] = GameSprites.creatureFrames(kind)
		return HStack(spacing: 8) {
			ForEach(0..<min(6, bufs.count), id: \.self) { (i: Int) in
				pixImage(bufs[i]).resizable().interpolation(.none).frame(width: 44, height: 44).background(Color.black.opacity(0.35))
			}
			Spacer()
			SmallButton(title: "EDIT ITS SPRITE", color: ModUI.accent) { self.startEditing() }
		}
	}

	func editor(_ fr: [ModPixels]) -> some View {
		let i: Int = min(frame, fr.count - 1)
		return VStack(alignment: .leading, spacing: 8) {
			frameRow(fr.count)
			PixelEditorView(pixels: frameBind(i), maxSide: 360, frames: fr, frameIndex: i, sizes: [], outlineDefault: false)
			HStack(spacing: 6) {
				SmallButton(title: "BACK TO THE GAME'S SPRITE", color: ModUI.red) { self.setFrames(nil) }
				SmallButton(title: "SAVE AS A NEW CREATURE", color: ModUI.blue) { self.saveAsCreature() }
			}
		}
	}

	func frameRow(_ n: Int) -> some View {
		HStack(spacing: 6) {
			ForEach(0..<n, id: \.self) { (i: Int) in
				SmallButton(title: joinText("FRAME ", String(i + 1)), color: self.frame == i ? ModUI.accent : Color(ui: 0x555555)) { self.frame = i }
			}
			if n < 12 { SmallButton(title: "+ FRAME", color: ModUI.blue) { self.copyFrame() } }
			if n > 1 { SmallButton(title: "DELETE FRAME", color: ModUI.red) { self.deleteFrame() } }
		}
	}

	func frameBind(_ i: Int) -> Binding<ModPixels> {
		return Binding<ModPixels>(get: {
			let fr: [ModPixels] = self.override.frames ?? []
			return i < fr.count ? fr[i] : ModPixels(w: 24, h: 24)
		}, set: { (v: ModPixels) in
			var fr: [ModPixels] = self.override.frames ?? []
			if i < fr.count {
				fr[i] = v
				self.setFrames(fr)
			}
		})
	}

	func setFrames(_ fr: [ModPixels]?) {
		guard let k = s.mod.overrides.firstIndex(where: { $0.id == id }) else { return }
		s.mod.overrides[k].frames = fr
		s.touch()
		if fr == nil { frame = 0 }
	}

	/// The game's own frames, copied in to paint over (they already have the game's outline)
	func startEditing() {
		let bufs: [PixelBuf] = GameSprites.creatureFrames(kind)
		guard let f0 = bufs.first else { return }
		if f0.w > ModPixels.maxSide || f0.h > ModPixels.maxSide {
			note = joinText("Its sprite is too big to paint here (", String(f0.w), " x ", String(f0.h), ").")
			return
		}
		var fr: [ModPixels] = []
		for b in bufs {
			var p: ModPixels = ModPixels(buf: b)
			p.outline = false
			fr.append(p)
		}
		frame = 0
		setFrames(fr)
		// the repaint follows the drawing it starts from: its size and the order of its frames
		if let k = s.mod.overrides.firstIndex(where: { $0.id == id }) {
			s.mod.overrides[k].fine = creatureLook(kind, 0).fine
			s.touch()
		}
	}

	func copyFrame() {
		var fr: [ModPixels] = override.frames ?? []
		if fr.isEmpty || fr.count >= 12 { return }
		let i: Int = min(frame, fr.count - 1)
		fr.insert(fr[i], at: i + 1)
		setFrames(fr)
		frame = i + 1
	}

	func deleteFrame() {
		var fr: [ModPixels] = override.frames ?? []
		if fr.count <= 1 { return }
		fr.remove(at: min(frame, fr.count - 1))
		setFrames(fr)
		frame = max(0, min(frame, fr.count - 1))
	}

	/// A new custom creature with this sprite and the game creature's numbers (its body and hit box
	/// come from the game creature): standing, two walking frames, and its attack
	func saveAsCreature() {
		let fr: [ModPixels] = override.frames ?? []
		if fr.isEmpty { return }
		let k: MobKind = kind
		let d: MobDef = makeMobDef(k)
		let anim: CreatureAnim = override.fine ? creatureLook(k, 0).anim : olderCreatureArt(k, 0).1
		var m = ModMob()
		m.id = s.mod.freshID("m")
		m.name = String(joinText(d.name, " (own look)").prefix(32))
		m.base = k.rawValue
		m.customArt = true
		// standing, two frames of the walk (the first and one half a stride on), and the attack
		let w0: Int = anim.walk.first ?? 1
		let w1: Int = anim.walk.count > 2 ? anim.walk[anim.walk.count / 2] : (anim.walk.last ?? 2)
		var pick: [Int] = [0, min(w0, fr.count - 1), min(w1, fr.count - 1)]
		let hit: Int = anim.attack >= 0 ? anim.attack : anim.pose("strike", fr.count - 1)
		pick.append(hit >= 0 && hit < fr.count ? hit : fr.count - 1)
		m.frames = pick.map { fr[$0] }
		m.hp = d.hp
		m.damage = d.dmg
		m.speed = d.speed
		m.detect = d.aggro
		m.jump = d.jump
		m.category = d.hostile ? .hostile : (d.flying ? .flying : .passive)
		s.mod.mobs.append(m)
		s.touch()
		note = joinText("Saved as a new creature, \u{201C}", m.name, "\u{201D}, in CREATURES.")
	}
}

/// Editing one change to game content, with what it does before and after
struct OverrideEditorView: View {
	@ObservedObject var s: ModSession
	let id: String

	var body: some View {
		guard let o = s.mod.overrides.first(where: { $0.id == id }) else {
			return AnyView(Text("This change no longer exists.").font(.pixel(13)).foregroundColor(ModUI.dim))
		}
		return AnyView(VStack(alignment: .leading, spacing: 10) {
			header(o)
			ModToggle(label: "This change is on", help: "Off: the game's own numbers, kept with the mod for later", isOn: s.bind(\.overrides, id, \.enabled, true))
			fields(o)
			preview(o)
		})
	}

	func header(_ o: ModOverride) -> some View {
		HStack(spacing: 10) {
			overrideIcon(o).resizable().interpolation(.none).frame(width: 56, height: 56).background(Color.black.opacity(0.4))
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: o.targetName).font(.pixel(18)).foregroundColor(Color.white)
				Text(verbatim: o.kind.name).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer()
			SmallButton(title: "RESTORE ALL", color: Color(ui: 0x6A5A3A)) { self.restoreAll() }
		}
	}

	func preview(_ o: ModOverride) -> some View {
		let rows: [(String, String, String)] = previewRows(o)
		return ModSection(title: "BEFORE AND AFTER", help: "Worked out with the game's own rules") {
			ForEach(0..<rows.count, id: \.self) { i in PreviewRow(name: rows[i].0, before: rows[i].1, after: rows[i].2) }
		}
	}

	func restoreAll() {
		guard let i = s.mod.overrides.firstIndex(where: { $0.id == id }) else { return }
		var o: ModOverride = s.mod.overrides[i]
		let keep: ModOverride = o
		o = ModOverride()
		o.id = keep.id
		o.kind = keep.kind
		o.tile = keep.tile
		o.item = keep.item
		o.mob = keep.mob
		o.enabled = keep.enabled
		s.mod.overrides[i] = o
		s.touch()
	}

	func b(_ kp: WritableKeyPath<ModOverride, Double?>) -> Binding<Double?> {
		return s.bind(\.overrides, id, kp, nil)
	}

	func bi(_ kp: WritableKeyPath<ModOverride, Int?>) -> Binding<Double?> {
		let inner: Binding<Int?> = s.bind(\.overrides, id, kp, nil)
		return Binding<Double?>(get: { inner.wrappedValue.map { Double($0) } }, set: { v in inner.wrappedValue = v.map { Int($0.rounded()) } })
	}

	func unbreakableBind() -> Binding<Bool> {
		let inner: Binding<Bool?> = s.bind(\.overrides, id, \.unbreakable, nil)
		return Binding<Bool>(get: { inner.wrappedValue ?? false }, set: { v in inner.wrappedValue = v ? true : nil })
	}

	func fields(_ o: ModOverride) -> AnyView {
		switch o.kind {
		case .block: return blockFields(o)
		case .item: return itemFields(o)
		case .creature: return creatureFields(o)
		}
	}

	func blockFields(_ o: ModOverride) -> AnyView {
		let sb: Bool = s.mod.sandbox
		let t: Tile = Tile(rawValue: UInt8(clampI(o.tile, 0, 255))) ?? .stone
		let d: TileDef = Tile.makeDef(t)
		let top: Double = sb ? 200 : 40
		let tier: Double = Double(d.tier)
		let light: Double = Double(d.light)
		return AnyView(VStack(alignment: .leading, spacing: 8) {
			OverrideField(label: "Hardness", original: min(d.hard, top), value: b(\.hardness), range: 0.05...top, step: 0.05, format: "%.2f")
			OverrideField(label: "Tool tier needed", original: tier, value: bi(\.tier), range: 0.0...9.0, step: 1, format: "%.0f")
			OverrideField(label: "Light given off", original: light, value: bi(\.light), range: 0.0...15.0, step: 1, format: "%.0f")
			ModToggle(label: "Unbreakable", help: "Nothing can mine it", isOn: unbreakableBind())
		})
	}

	func itemFields(_ o: ModOverride) -> AnyView {
		let sb: Bool = s.mod.sandbox
		let it: Item = o.item ?? .sword(.iron)
		let p: MeleeProfile = it.baseMelee
		let dmgR: ClosedRange<Double> = sbRange(0, 60, 500, sb)
		switch it {
		case .armor(let sl, let tr):
			let d0: Double = tr.defense * sl.weight
			return AnyView(OverrideField(label: "Defence", original: d0, value: b(\.defense), range: sbRange(0, 12, 40, sb), step: 0.1))
		case .food(let f):
			return AnyView(VStack(alignment: .leading, spacing: 8) {
				OverrideField(label: "Hunger restored", original: f.hunger, value: b(\.hunger), range: 0.0...20.0, step: 0.5)
				OverrideField(label: "Health restored", original: f.heal, value: b(\.heal), range: sbRange(0, 40, 400, sb), step: 0.5)
			})
		case .gun(let g):
			return AnyView(VStack(alignment: .leading, spacing: 8) {
				OverrideField(label: "Shot damage", original: g.damage, value: b(\.damage), range: dmgR, step: 0.5)
				OverrideField(label: "Time between shots", original: g.cooldown, value: b(\.cooldown), range: 0.15...10.0, step: 0.05, format: "%.2f")
			})
		case .bow, .sling:
			let base: Double = it == .bow ? 14 : 4.5
			return AnyView(OverrideField(label: "Shot damage (full draw)", original: base, value: b(\.damage), range: dmgR, step: 0.5))
		case .tool(_, let tr):
			return AnyView(VStack(alignment: .leading, spacing: 8) {
				OverrideField(label: "Mining speed", original: tr.mineSpeed, value: b(\.mineSpeed), range: sbRange(0.3, 30, 200, sb), step: 0.1)
				OverrideField(label: "Damage when swung", original: p.damage, value: b(\.damage), range: dmgR, step: 0.5)
			})
		default:
			return AnyView(VStack(alignment: .leading, spacing: 8) {
				OverrideField(label: "Damage", original: p.damage, value: b(\.damage), range: dmgR, step: 0.5)
				OverrideField(label: "Time between swings", original: p.cooldown, value: b(\.cooldown), range: 0.15...10.0, step: 0.01, format: "%.2f")
				OverrideField(label: "Reach", original: p.reach, value: b(\.reach), range: sbRange(0.5, 6, 12, sb), step: 0.1)
				OverrideField(label: "Knockback", original: p.knock, value: b(\.knock), range: sbRange(0, 16, 40, sb), step: 0.5)
				OverrideField(label: "Critical chance", original: p.critChance, value: b(\.crit), range: 0.0...1.0, step: 0.01, format: "%.2f")
			})
		}
	}

	func creatureFields(_ o: ModOverride) -> AnyView {
		let sb: Bool = s.mod.sandbox
		let k: MobKind = MobKind(rawValue: o.mob) ?? .zombie
		let d: MobDef = makeMobDef(k)
		return AnyView(VStack(alignment: .leading, spacing: 8) {
			OverrideField(label: "Health", original: d.hp, value: b(\.hp), range: sbRange(1, 4000, 20000, sb), step: 1, format: "%.0f")
			OverrideField(label: "Damage", original: d.dmg, value: b(\.mobDamage), range: sbRange(0, 60, 500, sb), step: 0.5)
			OverrideField(label: "Speed", original: d.speed, value: b(\.speed), range: sbRange(0, 8, 20, sb), step: 0.1)
			OverrideField(label: "Notices you from", original: d.aggro, value: b(\.detect), range: sbRange(2, 32, 64, sb), step: 1, format: "%.0f")
			OverrideField(label: "Jump", original: d.jump, value: b(\.jump), range: sbRange(0, 20, 30, sb), step: 0.5)
			CreatureSpriteEditor(s: s, id: id)
		})
	}

	/// Before-and-after numbers for the preview
	func previewRows(_ o: ModOverride) -> [(String, String, String)] {
		switch o.kind {
		case .block: return blockRows(o)
		case .item: return itemRows(o)
		case .creature: return creatureRows(o)
		}
	}

	func blockRows(_ o: ModOverride) -> [(String, String, String)] {
		var rows: [(String, String, String)] = []
		let t: Tile = Tile(rawValue: UInt8(clampI(o.tile, 0, 255))) ?? .stone
		let d: TileDef = Tile.makeDef(t)
		let hard1: Double = o.unbreakable == true ? 9999 : (o.hardness ?? d.hard)
		let tier1: Int = o.tier ?? d.tier
		let cls: ToolType = toolClass(t)
		let toolName: String = cls.name.lowercased()
		let tools: [(String, ToolType?, Tier)] = [("Bare hands", nil, .wood), (joinText("Wooden ", toolName), cls, .wood),
												   (joinText("Iron ", toolName), cls, .iron), (joinText("Diamond ", toolName), cls, .diamond)]
		for (name, k, tr) in tools {
			let tierN: Int = k == nil ? 0 : tr.rawValue
			let speed: Double = tr.mineSpeed
			let a: Double? = miningSecondsFor(hardness: d.hard, tier: d.tier, blockTool: cls, unbreakable: d.hard >= 9999, k, tierN, toolSpeed: speed)
			let bb: Double? = miningSecondsFor(hardness: hard1, tier: tier1, blockTool: cls, unbreakable: hard1 >= 9999, k, tierN, toolSpeed: speed)
			rows.append((name, secondsText(a), secondsText(bb)))
		}
		let l1: Int = o.light ?? d.light
		rows.append(("Light", String(d.light), String(l1)))
		return rows
	}

	func itemRows(_ o: ModOverride) -> [(String, String, String)] {
		var rows: [(String, String, String)] = []
		let it: Item = o.item ?? .sword(.iron)
		let p0: MeleeProfile = it.baseMelee
		let p1: MeleeProfile = o.apply(p0)
		switch it {
		case .armor(let sl, let tr):
			let d0: Double = tr.defense * sl.weight
			let d1: Double = o.defense ?? d0
			rows.append(("Defence", oneDecimal(d0), oneDecimal(d1)))
		case .food(let f):
			let h1: Double = o.hunger ?? f.hunger
			let l1: Double = o.heal ?? f.heal
			rows.append(("Hunger", oneDecimal(f.hunger), oneDecimal(h1)))
			rows.append(("Health", oneDecimal(f.heal), oneDecimal(l1)))
		case .tool(_, let tr):
			let speed: Double = o.mineSpeed ?? tr.mineSpeed
			let s0: Double? = miningSeconds(.stone, .pickaxe, tr)
			let s1: Double? = miningSeconds(.stone, .pickaxe, tr, toolSpeed: speed)
			rows.append(("Stone takes (as a pickaxe)", secondsText(s0), secondsText(s1)))
		case .gun(let g):
			let dmg1: Double = o.damage ?? g.damage
			let cd1: Double = o.cooldown ?? g.cooldown
			let dps0: Double = g.damage / max(0.05, g.cooldown)
			let dps1: Double = dmg1 / max(0.05, cd1)
			rows.append(("Damage a second", oneDecimal(dps0), oneDecimal(dps1)))
		default:
			let dps0: Double = p0.damage / max(0.05, p0.cooldown)
			let dps1: Double = p1.damage / max(0.05, p1.cooldown)
			let z: Double = mobDef(.zombie).hp
			let blows0: Int = Int(ceil(z / max(0.1, p0.damage)))
			let blows1: Int = Int(ceil(z / max(0.1, p1.damage)))
			rows.append(("Damage", oneDecimal(p0.damage), oneDecimal(p1.damage)))
			rows.append(("Damage a second", oneDecimal(dps0), oneDecimal(dps1)))
			rows.append(("Blows to fell a zombie", String(blows0), String(blows1)))
		}
		return rows
	}

	func creatureRows(_ o: ModOverride) -> [(String, String, String)] {
		var rows: [(String, String, String)] = []
		let k: MobKind = MobKind(rawValue: o.mob) ?? .zombie
		let d: MobDef = makeMobDef(k)
		let sword: Double = Item.sword(.iron).baseMelee.damage
		let hp1: Double = o.hp ?? d.hp
		let blows0: Int = Int(ceil(d.hp / sword))
		let blows1: Int = Int(ceil(hp1 / sword))
		rows.append(("Iron sword blows to fell it", String(blows0), String(blows1)))
		rows.append(("Its blow (before armour)", oneDecimal(d.dmg), oneDecimal(o.mobDamage ?? d.dmg)))
		rows.append(("Speed", oneDecimal(d.speed), oneDecimal(o.speed ?? d.speed)))
		return rows
	}
}

/// A slider's range: its top in normal play, or in sandbox mode
func sbRange(_ lo: Double, _ hi: Double, _ sbHi: Double, _ sb: Bool) -> ClosedRange<Double> {
	let top: Double = sb ? sbHi : hi
	return lo...top
}

/// A number with one decimal place ("4.5")
func oneDecimal(_ v: Double) -> String { return String(format: "%.1f", v) }

/// Folders, saved versions and the mods this one needs (on the INFO tab)
struct ModOrganizeSection: View {
	@ObservedObject var s: ModSession
	@State var label: String = ""
	@State var versions: [ModVersionInfo] = []
	@State var note: String = ""
	@State var loaded: Bool = false
	@State var confirmFile: String = ""
	/// the other installed mods (read when the section opens and after a change)
	@State var entries: [ModEntry] = []
	@State var folders: [String] = []

	var body: some View {
		VStack(spacing: 10) {
			folderSection
			needsSection
			versionsSection
		}
		.onAppear { self.load() }
	}

	func load() {
		if loaded { return }
		loaded = true
		refresh()
	}

	func refresh() {
		versions = ModStore.versions(s.mod.id)
		let me: String = s.mod.id
		entries = ModStore.entries().filter { $0.id != me }
		folders = ModStore.folders()
	}

	var folderSection: some View {
		let names: [String] = Array(folders.prefix(6))
		return ModSection(title: "FOLDER", help: "Mods in the same folder are listed together") {
			ModTextField(label: "Folder", text: s.modBind(\.folder), placeholder: "e.g. Monsters")
			if !names.isEmpty {
				HStack(spacing: 6) {
					ForEach(names, id: \.self) { f in self.folderButton(f) }
				}
			}
		}
	}

	func folderButton(_ f: String) -> some View {
		let col: Color = s.mod.folder == f ? ModUI.accent : Color(ui: 0x4A4A50)
		return SmallButton(title: f, color: col) {
			self.s.mod.folder = f
			self.s.touch()
		}
	}

	var needsSection: some View {
		let deps: [String] = ModStore.dependencies(s.mod)
		let others: [ModEntry] = Array(entries.filter { e in !deps.contains(e.id) && e.pack != nil }.prefix(5))
		return ModSection(title: "NEEDS OTHER MODS", help: "A world using this mod needs these too. Mods whose blocks or items this one uses are found by themselves.") {
			if deps.isEmpty { Text("None.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim) }
			ForEach(deps, id: \.self) { d in self.depRow(d) }
			if !others.isEmpty {
				Text("Add a mod it needs:").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
				HStack(spacing: 6) {
					ForEach(others) { e in self.addDepButton(e) }
				}
			}
		}
	}

	func depRow(_ d: String) -> some View {
		let e: ModEntry? = entries.first { $0.id == d }
		let name: String = e?.pack?.name ?? joinText("Missing mod (", d, ")")
		var state: String = "not installed"
		if let x = e { state = x.enabled ? "on" : "off" }
		let col: Color = e == nil ? Color(ui: 0xFF9A7A) : Color.white
		let mine: Bool = s.mod.requires.contains(d)
		return HStack {
			Text(verbatim: name).font(.pixel(12)).foregroundColor(col)
			Text(verbatim: state).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			Spacer()
			if mine {
				SmallButton(title: "REMOVE", color: ModUI.red) { self.removeDep(d) }
			}
		}
	}

	func removeDep(_ d: String) {
		s.mod.requires.removeAll { $0 == d }
		s.touch()
	}

	func addDepButton(_ e: ModEntry) -> some View {
		let name: String = e.pack?.name ?? e.id
		return SmallButton(title: name, color: ModUI.blue) {
			self.s.mod.requires.append(e.id)
			self.s.touch()
		}
	}

	var versionsSection: some View {
		let hint: String = joinText("Version ", s.mod.version)
		return ModSection(title: "SAVED VERSIONS", help: "Keep a copy of the mod as it is now, and go back to it later (the last 12 are kept)") {
			HStack(spacing: 6) {
				ModTextField(label: "Name for this version", text: $label, placeholder: hint)
				SmallButton(title: "SAVE VERSION", color: ModUI.accent) { self.saveVersion() }
			}
			if !note.isEmpty { Text(verbatim: note).font(.pixel(11, .semibold)).foregroundColor(ModUI.gold) }
			ForEach(versions) { v in self.versionRow(v) }
		}
	}

	func saveVersion() {
		_ = s.save()
		let name: String = label.isEmpty ? joinText("Version ", s.mod.version) : label
		note = ModStore.saveVersion(s.mod, label: name) ? "Version saved." : "It could not be saved."
		label = ""
		versions = ModStore.versions(s.mod.id)
	}

	func versionRow(_ v: ModVersionInfo) -> some View {
		let sure: Bool = confirmFile == v.file
		let when: String = joinText("v", v.version, " \u{00B7} ", shortDate(v.time))
		let col: Color = Color(ui: sure ? 0xC04030 : 0x6A5A3A)
		return HStack {
			VStack(alignment: .leading, spacing: 1) {
				Text(verbatim: v.label).font(.pixel(12)).foregroundColor(Color.white)
				Text(verbatim: when).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer()
			SmallButton(title: sure ? "SURE?" : "RESTORE", color: col) { self.restore(v) }
			SmallButton(title: "\u{2715}", color: ModUI.red) { self.deleteVersion(v) }
		}
	}

	func restore(_ v: ModVersionInfo) {
		if confirmFile != v.file {
			confirmFile = v.file
			note = "Restoring replaces the mod as it is now (a copy of it is kept first). Tap SURE? to go ahead."
			return
		}
		confirmFile = ""
		if let p = ModStore.restoreVersion(s.mod.id, v.file) {
			s.mod = p
			s.dirty = false
			s.recheck()
			note = joinText("Restored ", v.label, ".")
		} else {
			note = "That version could not be read."
		}
		versions = ModStore.versions(s.mod.id)
	}

	func deleteVersion(_ v: ModVersionInfo) {
		ModStore.deleteVersion(v.file)
		versions = ModStore.versions(s.mod.id)
	}
}

extension ModCreatorView {
	/// The folders the mods are filed under: tap one to see only those mods
	var folderChips: some View {
		let names: [String] = ModStore.folders()
		return Group {
			if !names.isEmpty {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 6) {
						SmallButton(title: "ALL MODS", color: folder.isEmpty ? ModUI.accent : Color(ui: 0x4A4A50)) { folder = "" }
						ForEach(names, id: \.self) { f in
							SmallButton(title: f.uppercased(), color: folder == f ? ModUI.accent : Color(ui: 0x4A4A50)) { folder = f }
						}
					}
				}
			}
		}
	}
}

extension ModEditorView {
	/// Starting a new block, item or creature from one of the game's own (its picture and numbers)
	@ViewBuilder
	func fromGame(_ k: ModOverrideKind) -> some View {
		if gamePick == k {
			GamePickerView(kind: k, title: joinText("START FROM A ", k.name.uppercased()), pick: { raw, it in startFromGame(k, raw, it) }, cancel: { gamePick = nil })
		} else {
			SmallButton(title: joinText("+ START FROM A ", k.name.uppercased()), color: ModUI.blue) { gamePick = k }
		}
	}

	func startFromGame(_ k: ModOverrideKind, _ raw: Int, _ it: Item?) {
		gamePick = nil
		switch k {
		case .block:
			guard let t = Tile(rawValue: UInt8(clampI(raw, 0, 255))) else { return }
			var b: ModBlock = ModBlock.fromGame(t)
			b.id = session.mod.freshID("b")
			session.mod.blocks.append(b)
			session.touch()
			target = .block(b.id)
		case .item:
			guard let i = it else { return }
			var m: ModItem = ModItem.fromGame(i)
			m.id = session.mod.freshID("i")
			session.mod.items.append(m)
			session.touch()
			target = .item(m.id)
		case .creature:
			guard let kind = MobKind(rawValue: raw) else { return }
			var m: ModMob = ModMob.fromGame(kind)
			m.id = session.mod.freshID("c")
			session.mod.mobs.append(m)
			session.touch()
			target = .mob(m.id)
		}
	}

	/// Switches a piece of content off for now (it stays in the mod) or back on
	func toggleOff(_ id: String) {
		if session.mod.off.contains(id) {
			session.mod.off.removeAll { $0 == id }
		} else {
			session.mod.off.append(id)
		}
		session.touch()
	}
}

// MARK: - Mod Creator+: ore controls, the generation preview and the hardness reference

/// More ore controls: where in the ground, what shape, how often, which biomes, which host blocks,
/// near which other ore, and a preview made by the real world generator
struct OreControlsView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var preview: PixelBuf? = nil
	@State var previewCount: Int = 0
	@State var previewRev: Int = -1

	func b<T>(_ kp: WritableKeyPath<ModOre, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.ores, id, kp, d) }
	var ore: ModOre { return s.mod.ores.first { $0.id == id } ?? ModOre() }

	var body: some View {
		let o: ModOre = ore
		return VStack(spacing: 10) {
			whereSection(o)
			ModSection(title: "HOST BLOCKS", help: "Pick the exact blocks it may replace (none picked: the \u{201C}Forms in\u{201D} choice above)") {
				hostChips(o)
			}
			ModSection(title: "NEAR ANOTHER ORE", help: "Veins only start within three blocks of this one") {
				nearChips(o)
			}
			previewSection
		}
	}

	func whereSection(_ o: ModOre) -> some View {
		let help: String = ModOre.placeHelp[clampI(o.place, 0, 3)]
		return ModSection(title: "WHERE IT FORMS") {
			ChoiceRow(options: ModOre.placeNames, selected: b(\.place, 0), columns: 2)
			Text(verbatim: help).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			Text("Vein shape").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			ChoiceRow(options: ModOre.shapeNames, selected: b(\.shape, 0), columns: 3)
			StatSlider(label: "Chance a stretch of ground has it", value: b(\.rarity, 1), range: 0.02...1.0, step: 0.01, format: "%.2f")
			ModBiomePicker(biomes: b(\.biomes, []))
		}
	}

	var previewSection: some View {
		ModSection(title: "PREVIEW", help: "A slice of a sample world, made by the game's own generator: the pink is your ore") {
			HStack(alignment: .top, spacing: 12) {
				previewImage
				previewNotes
			}
		}
	}

	var previewImage: AnyView {
		guard let img = preview else { return AnyView(EmptyView()) }
		let w: CGFloat = CGFloat(img.w * 2)
		let h: CGFloat = CGFloat(img.h)
		return AnyView(pixImage(img).resizable().interpolation(.none).frame(width: w, height: h)
			.overlay(Rectangle().stroke(Color.white.opacity(0.3), lineWidth: 1)))
	}

	var previewNotes: some View {
		let made: Bool = preview != nil
		let title: String = made ? "MAKE IT AGAIN" : "MAKE PREVIEW"
		let count: String = joinText(String(previewCount), " blocks in ", String(ModOrePreview.chunks * chunkW), " columns")
		let fresh: String = previewRev == s.rev ? "Up to date." : "Settings changed since: make it again."
		return VStack(alignment: .leading, spacing: 6) {
			SmallButton(title: title, color: ModUI.blue) { self.makePreview() }
			if made {
				Text(verbatim: count).font(.pixel(11, .semibold)).foregroundColor(Color.white)
				Text(verbatim: fresh).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
				Text("Sky blue, caves black, water blue, lava orange.").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
		}
	}

	func makePreview() {
		let r: (PixelBuf, Int) = ModOrePreview.render(ore, s.mod)
		preview = r.0
		previewCount = r.1
		previewRev = s.rev
	}

	func hostChips(_ o: ModOre) -> some View {
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 100), spacing: 6)]
		var keys: [String] = ModGround.hosts.map { ModGround.key($0) }
		for blk in s.mod.blocks where blk.id != o.block { keys.append(s.mod.key(blk.id)) }
		let chosen: [String] = o.hosts
		return LazyVGrid(columns: cols, spacing: 6) {
			ForEach(keys, id: \.self) { k in
				ToggleChip(title: ModGround.name(k, self.s.mod), on: chosen.contains(k)) { self.flipHost(k) }
			}
		}
	}

	func flipHost(_ k: String) {
		let hosts: Binding<[String]> = b(\.hosts, [])
		if hosts.wrappedValue.contains(k) {
			hosts.wrappedValue.removeAll { $0 == k }
		} else if hosts.wrappedValue.count < 8 {
			hosts.wrappedValue.append(k)
		}
	}

	func nearChips(_ o: ModOre) -> some View {
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 100), spacing: 6)]
		var keys: [String] = [""] + ModGround.ores.map { ModGround.key($0) }
		for blk in s.mod.blocks where blk.id != o.block { keys.append(s.mod.key(blk.id)) }
		let cur: String = o.near
		return LazyVGrid(columns: cols, spacing: 6) {
			ForEach(keys, id: \.self) { k in
				ToggleChip(title: k.isEmpty ? "ANYWHERE" : ModGround.name(k, self.s.mod), on: cur == k) { self.b(\.near, "").wrappedValue = k }
			}
		}
	}
}

/// How long a mod block takes to break with each tool, worked out with the game's own mining rules
struct BlockMiningTimes: View {
	let block: ModBlock
	let tools: [ModItem]

	var body: some View {
		let cls: ToolType = ToolType(rawValue: block.tool) ?? .pickaxe
		let tiers: [Tier] = [.wood, .stone, .iron, .diamond, .voidium]
		return ModSection(title: "MINING TIMES", help: "From the game's own mining rules") {
			row("Bare hands", miningSecondsFor(hardness: block.hardness, tier: block.tier, blockTool: cls, unbreakable: block.unbreakable, nil, 0, toolSpeed: 1))
			ForEach(tiers, id: \.self) { t in
				row(joinText(t.name, " ", cls.name.lowercased()), miningSecondsFor(hardness: block.hardness, tier: block.tier, blockTool: cls, unbreakable: block.unbreakable, cls, t.rawValue, toolSpeed: t.mineSpeed))
			}
			ForEach(tools) { it in
				let k: ToolType = ToolType(rawValue: it.toolType) ?? .pickaxe
				row(joinText(it.name, " (yours)"), miningSecondsFor(hardness: block.hardness, tier: block.tier, blockTool: cls, unbreakable: block.unbreakable, k, it.toolTier, toolSpeed: it.toolSpeed))
			}
		}
	}

	func row(_ name: String, _ t: Double?) -> some View {
		HStack {
			Text(verbatim: name).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			Spacer()
			Text(verbatim: secondsText(t)).font(.pixel(11)).foregroundColor(t == nil ? Color(ui: 0xFF9A7A) : Color.white)
		}
	}
}

/// Every game block with its hardness, the tool that mines it, the tier it needs, and how long each
/// tool takes (the mod's own tools too), all from the game's mining rules
struct HardnessReferenceView: View {
	@ObservedObject var s: ModSession
	@State var filter: String = ""
	@State var picked: Int = Int(Tile.stone.rawValue)

	var body: some View {
		let tiles: [Tile] = ModOverrideCheck.tiles().filter { t in filter.isEmpty || t.name.lowercased().contains(filter.lowercased()) }
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 120), spacing: 6)]
		let t: Tile = Tile(rawValue: UInt8(clampI(picked, 0, 255))) ?? .stone
		return VStack(alignment: .leading, spacing: 10) {
			Text("The game's blocks and how hard they are. Tap one to see every tool's mining time.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			detail(t)
			ModTextField(label: "Search", text: $filter, placeholder: "block name")
			LazyVGrid(columns: cols, spacing: 6) {
				ForEach(tiles, id: \.self) { tile in
					Button { picked = Int(tile.rawValue) } label: {
						HStack(spacing: 6) {
							pixImage(tileBuf(tile)).resizable().interpolation(.none).frame(width: 26, height: 26)
							VStack(alignment: .leading, spacing: 1) {
								Text(verbatim: tile.name).font(.pixel(10)).foregroundColor(Color.white).lineLimit(1)
								Text(verbatim: tile.def.hard >= 9999 ? "unbreakable" : String(format: "hardness %.2f", tile.def.hard)).font(.pixel(9, .semibold)).foregroundColor(ModUI.dim)
							}
							Spacer(minLength: 0)
						}
						.padding(4)
						.background(picked == Int(tile.rawValue) ? ModUI.accent : ModUI.card)
					}
					.buttonStyle(.plain)
				}
			}
		}
	}

	func detail(_ t: Tile) -> some View {
		let cls: ToolType = toolClass(t)
		let d: TileDef = t.def
		let tools: [ModItem] = s.mod.items.filter { $0.kind == .tool }
		return ModSection(title: t.name.uppercased()) {
			HStack(spacing: 10) {
				pixImage(tileBuf(t)).resizable().interpolation(.none).frame(width: 48, height: 48)
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: d.hard >= 9999 ? "Unbreakable" : String(format: "Hardness %.2f", d.hard)).font(.pixel(12)).foregroundColor(Color.white)
					Text(verbatim: joinText("Best tool: ", cls.name.lowercased(), d.tier > 0 ? joinText(" · needs tier ", String(d.tier), " (", Tier(rawValue: d.tier)?.name ?? "", ")") : " · any tool")).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				}
			}
			row("Bare hands", miningSeconds(t, nil, nil))
			ForEach(Tier.allCases, id: \.self) { tr in
				row(joinText(tr.name, " ", cls.name.lowercased()), miningSeconds(t, cls, tr))
			}
			let wrong: ToolType = cls == .pickaxe ? .axe : .pickaxe
			row(joinText("Iron ", wrong.name.lowercased(), " (wrong tool)"), miningSeconds(t, wrong, .iron))
			ForEach(tools) { it in
				let k: ToolType = ToolType(rawValue: it.toolType) ?? .pickaxe
				let tier: Tier = Tier(rawValue: clampI(it.toolTier, 1, 9)) ?? .wood
				row(joinText(it.name, " (yours)"), miningSeconds(t, k, tier, toolSpeed: it.toolSpeed))
			}
		}
	}

	func row(_ name: String, _ v: Double?) -> some View {
		HStack {
			Text(verbatim: name).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			Spacer()
			Text(verbatim: secondsText(v)).font(.pixel(11)).foregroundColor(v == nil ? Color(ui: 0xFF9A7A) : Color.white)
		}
	}
}

// MARK: - Mod Creator+: the Sprite Studio

/// The Sprite Studio's tools
enum SpriteTool: Int, CaseIterable {
	case pen, erase, fill, pick, line, box, circle, select, shade, dither, pan
	var name: String {
		switch self {
		case .pen: return "PEN"
		case .erase: return "ERASE"
		case .fill: return "FILL"
		case .pick: return "PICK"
		case .line: return "LINE"
		case .box: return "BOX"
		case .circle: return "CIRCLE"
		case .select: return "SELECT"
		case .shade: return "SHADE"
		case .dither: return "DITHER"
		case .pan: return "PAN"
		}
	}
	/// tools that paint with the brush as the finger moves
	var brush: Bool { return self == .pen || self == .erase || self == .shade || self == .dither }
	/// tools drawn from where the finger went down to where it lifts
	var shape: Bool { return self == .line || self == .box || self == .circle }
}

/// A rectangle of pixels the SELECT tool has chosen (inclusive corners)
struct SpriteSel: Equatable {
	var x0: Int
	var y0: Int
	var x1: Int
	var y1: Int
	var w: Int { return x1 - x0 + 1 }
	var h: Int { return y1 - y0 + 1 }
	func contains(_ x: Int, _ y: Int) -> Bool { return x >= x0 && x <= x1 && y >= y0 && y <= y1 }
	static func from(_ a: (Int, Int), _ b: (Int, Int)) -> SpriteSel {
		return SpriteSel(x0: min(a.0, b.0), y0: min(a.1, b.1), x1: max(a.0, b.0), y1: max(a.1, b.1))
	}
}

/// One pixel painted in the current stroke, and what it was before (pixel-perfect lines put back the
/// corner pixel of an L, and shading touches each pixel once a stroke)
struct StrokeCell {
	var x: Int
	var y: Int
	var before: UInt32
}

/// How the Sprite Studio paints: brushes, opacity and blending, shading, shapes and selections. Pure
/// functions on a picture, so they are the same in the editor and the tests.
enum SpritePaint {
	/// the pixels a brush of this size and shape covers, centred on (x, y)
	static func brushCells(_ x: Int, _ y: Int, _ size: Int, _ round: Bool) -> [(Int, Int)] {
		let s: Int = clampI(size, 1, 8)
		if s == 1 { return [(x, y)] }
		var out: [(Int, Int)] = []
		let lo: Int = -(s - 1) / 2
		let hi: Int = s / 2
		let r: Double = Double(s) * 0.5
		for dy in lo...hi {
			for dx in lo...hi {
				if round {
					let fx: Double = Double(dx) - Double(lo + hi) * 0.5
					let fy: Double = Double(dy) - Double(lo + hi) * 0.5
					if fx * fx + fy * fy > r * r + 0.25 { continue }
				}
				out.append((x + dx, y + dy))
			}
		}
		return out
	}

	/// `src` laid over `dst` (both 0xAARRGGBB, not premultiplied)
	static func over(_ src: UInt32, _ dst: UInt32) -> UInt32 {
		let sa: Double = Double(src >> 24) / 255.0
		if sa >= 0.999 { return src }
		let da: Double = Double(dst >> 24) / 255.0
		let oa: Double = sa + da * (1.0 - sa)
		if oa <= 0.001 { return 0 }
		let k: Double = da * (1.0 - sa)
		let r: Double = (Double((src >> 16) & 0xFF) * sa + Double((dst >> 16) & 0xFF) * k) / oa
		let g: Double = (Double((src >> 8) & 0xFF) * sa + Double((dst >> 8) & 0xFF) * k) / oa
		let b: Double = (Double(src & 0xFF) * sa + Double(dst & 0xFF) * k) / oa
		let a: UInt32 = UInt32(clampD(oa * 255.0, 0, 255).rounded())
		return (a << 24) | (UInt32(clampD(r, 0, 255).rounded()) << 16) | (UInt32(clampD(g, 0, 255).rounded()) << 8) | UInt32(clampD(b, 0, 255).rounded())
	}

	/// The colour as the pen lays it: its opacity scaled by the pen's
	static func penColor(_ c: UInt32, _ opacity: Double) -> UInt32 {
		let a: Double = Double(c >> 24) * clampD(opacity, 0.05, 1)
		return (UInt32(clampD(a, 8, 255).rounded()) << 24) | (c & 0xFFFFFF)
	}

	/// One pixel painted: laid over what is there (blend), or set as it is (then a part see-through
	/// colour makes a part see-through pixel)
	static func paint(_ px: inout ModPixels, _ x: Int, _ y: Int, _ c: UInt32, _ blend: Bool) {
		if blend { px.setARGB(x, y, over(c, px.argb(x, y))) } else { px.setARGB(x, y, c) }
	}

	/// Rubbing out: all of it at full strength, some of its opacity at less
	static func erase(_ px: inout ModPixels, _ x: Int, _ y: Int, _ opacity: Double) {
		if opacity >= 0.99 { px.setARGB(x, y, 0); return }
		let c: UInt32 = px.argb(x, y)
		if c == 0 { return }
		let a: Double = Double(c >> 24) * (1.0 - clampD(opacity, 0, 1))
		px.setARGB(x, y, a < 8 ? 0 : ((UInt32(a.rounded()) << 24) | (c & 0xFFFFFF)))
	}

	/// Shading: a shade darker or lighter, its opacity kept
	static func shade(_ px: inout ModPixels, _ x: Int, _ y: Int, _ darker: Bool) {
		let c: UInt32 = px.argb(x, y)
		if c == 0 { return }
		px.setARGB(x, y, (c & 0xFF000000) | shadeRGB(c & 0xFFFFFF, darker ? 0.82 : 1.2))
	}

	/// A box, its edge or filled
	static func boxCells(_ a: (Int, Int), _ b: (Int, Int), _ filled: Bool) -> [(Int, Int)] {
		var out: [(Int, Int)] = []
		let x0: Int = min(a.0, b.0)
		let x1: Int = max(a.0, b.0)
		let y0: Int = min(a.1, b.1)
		let y1: Int = max(a.1, b.1)
		for y in y0...y1 {
			for x in x0...x1 where filled || x == x0 || x == x1 || y == y0 || y == y1 { out.append((x, y)) }
		}
		return out
	}

	/// An ellipse fitted in the box from a to b, its edge or filled
	static func ellipseCells(_ a: (Int, Int), _ b: (Int, Int), _ filled: Bool) -> [(Int, Int)] {
		let x0: Int = min(a.0, b.0)
		let x1: Int = max(a.0, b.0)
		let y0: Int = min(a.1, b.1)
		let y1: Int = max(a.1, b.1)
		let cx: Double = Double(x0 + x1 + 1) * 0.5
		let cy: Double = Double(y0 + y1 + 1) * 0.5
		let rx: Double = Double(x1 - x0 + 1) * 0.5
		let ry: Double = Double(y1 - y0 + 1) * 0.5
		func inside(_ x: Int, _ y: Int) -> Bool {
			if x < x0 || x > x1 || y < y0 || y > y1 { return false }
			let dx: Double = (Double(x) + 0.5 - cx) / rx
			let dy: Double = (Double(y) + 0.5 - cy) / ry
			return dx * dx + dy * dy <= 1.0 + 0.12 / max(1.0, min(rx, ry))
		}
		var out: [(Int, Int)] = []
		for y in y0...y1 {
			for x in x0...x1 where inside(x, y) {
				let edge: Bool = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1)
				if filled || edge { out.append((x, y)) }
			}
		}
		return out
	}

	/// Pixel-perfect lines: when the newest pixel makes an L with the two before it, the corner
	/// pixel is put back (single-pixel lines stay one pixel thick)
	static func perfectCorner(_ stroke: [StrokeCell], _ x: Int, _ y: Int) -> Bool {
		if stroke.count < 2 { return false }
		let a: StrokeCell = stroke[stroke.count - 2]
		let b: StrokeCell = stroke[stroke.count - 1]
		if abs(a.x - x) != 1 || abs(a.y - y) != 1 { return false }
		return (b.x == a.x && b.y == y) || (b.y == a.y && b.x == x)
	}

	/// The pixels of a selection, lifted out of the picture
	static func cut(_ px: ModPixels, _ s: SpriteSel) -> ModPixels {
		var o = ModPixels(w: max(1, s.w), h: max(1, s.h))
		for y in 0..<s.h {
			for x in 0..<s.w { o.setARGB(x, y, px.argb(s.x0 + x, s.y0 + y)) }
		}
		return o
	}

	/// Pixels laid into the picture at (ox, oy); clear pixels leave what is under them
	static func drop(_ px: inout ModPixels, _ part: ModPixels, _ ox: Int, _ oy: Int) {
		for y in 0..<part.h {
			for x in 0..<part.w {
				let c: UInt32 = part.argb(x, y)
				if c != 0 { px.setARGB(ox + x, oy + y, over(c, px.argb(ox + x, oy + y))) }
			}
		}
	}

	static func clearSel(_ px: inout ModPixels, _ s: SpriteSel) {
		for y in s.y0...s.y1 {
			for x in s.x0...s.x1 { px.setARGB(x, y, 0) }
		}
	}
}

/// Colour sets for the Sprite Studio, and the player's own saved colours (kept on this iPad)
enum SpritePalettes {
	static let names: [String] = ["GAME", "EARTH", "METAL", "SKIN", "SKY", "FIRE", "GREYS", "MINE"]
	static let sets: [[UInt32]] = [
		modPalette,
		[0x2A1A10, 0x4A2E1A, 0x6A4224, 0x8A5A30, 0xAA7A44, 0xC89A5C, 0xE0BC80, 0xF0DCA8, 0x3A4A1E, 0x4E6A26, 0x5DAA3A, 0x8ACA5A,
		 0x5A5048, 0x7A7064, 0x9A9080, 0xC0B8A4],
		[0x1E2028, 0x3A3E4A, 0x5A606E, 0x7E8696, 0xA8B0BE, 0xD0D8E4, 0x6A4A20, 0xA8783A, 0xE0B050, 0xFFE08A, 0x4A1E1E, 0x8A3A2A,
		 0x2AA8A0, 0x6FE6EC, 0x8A3CD0, 0xD8A8FF],
		[0x3A2014, 0x6A3A24, 0x9A5A3A, 0xC88660, 0xE8B090, 0xF8D8C0, 0x7A2A3A, 0xC04A5A, 0x2A3A6A, 0x4A6AAA, 0x2A5A3A, 0x5A9A5A,
		 0xD8C8A0, 0xF0E8D0, 0x6A4A8A, 0xA88AC8],
		[0x0A1030, 0x1D2B53, 0x2A4A8A, 0x3E86D8, 0x6AA8F0, 0xB4DCFF, 0xF0F8FF, 0xFFFFFF, 0x0A3A4A, 0x1A6A7A, 0x3AA0B0, 0x7AD0D8,
		 0xF08A4A, 0xF0B06A, 0x8A6AB0, 0xC8A8E0],
		[0x3A0A0A, 0x7A1A0A, 0xB0300A, 0xE0601A, 0xFF8A30, 0xFFC050, 0xFFE88A, 0xFFFFD0, 0x2A0A3A, 0x5A1A8A, 0x9A3AE0, 0xC880FF,
		 0x0A3A2A, 0x1A8A5A, 0x3AE0A0, 0xA0FFD8],
		[0x000000, 0x111111, 0x222222, 0x333333, 0x444444, 0x555555, 0x666666, 0x777777, 0x888888, 0x999999, 0xAAAAAA, 0xBBBBBB,
		 0xCCCCCC, 0xDDDDDD, 0xEEEEEE, 0xFFFFFF]
	]
	static let key: String = "pr.sprite.myColours"

	/// The player's own colours (0xAARRGGBB, opacity kept)
	static func loadMine() -> [UInt32] {
		guard let list = UserDefaults.standard.array(forKey: key) as? [Int] else { return [] }
		return list.prefix(32).map { UInt32(truncatingIfNeeded: $0) }
	}

	static func saveMine(_ list: [UInt32]) {
		UserDefaults.standard.set(list.prefix(32).map { Int($0) }, forKey: key)
	}
}

/// The pixel editor used for every picture in the Mod Creator: zoom and pan, brushes of any size
/// (square or round) with opacity and blending, pixel-perfect lines, eraser, fill, colour picker,
/// lines, boxes and circles (open or filled), selections (move, copy, paste, flip, delete), shading
/// and dithering, mirror drawing, undo and redo, flips, shifts and turns, palettes and the player's
/// own colours, a reference picture beside or under the canvas (or copied in as a starting sample),
/// the outline switch, other sizes, copying in and out as text or a picture, the sprite library, and
/// onion skin and an animation preview for sprites with frames.
struct PixelEditorView: View {
	@Binding var pixels: ModPixels
	var maxSide: CGFloat = 320
	/// the sprite's other frames (onion skin and the animation preview)
	var frames: [ModPixels] = []
	var frameIndex: Int = 0
	/// sizes it may change to (empty: its size is fixed here)
	var sizes: [Int] = []
	/// the outline it has when none is chosen (creatures and items yes, blocks no)
	var outlineDefault: Bool = true
	/// called instead of resizing just this picture (a creature resizes all its frames together)
	var onResize: ((Int, Int) -> Void)? = nil

	@State var color: UInt32 = 0xFF5DAA3A
	@State var tool: Int = 0
	@State var mirror: Bool = false
	@State var undo: [ModPixels] = []
	@State var redo: [ModPixels] = []
	@State var stroking: Bool = false
	@State var lastCell: Int = -1
	@State var lastXY: (Int, Int)? = nil
	@State var mixR: Double = 120
	@State var mixG: Double = 160
	@State var mixB: Double = 90
	@State var showMixer: Bool = false
	@State var zoom: CGFloat = 0
	@State var panX: CGFloat = 0
	@State var panY: CGFloat = 0
	@State var panStart: CGPoint = .zero
	@State var shapeA: (Int, Int)? = nil
	@State var shapeB: (Int, Int)? = nil
	@State var recent: [UInt32] = []
	@State var showGrid: Bool = true
	@State var onion: Bool = true
	@State var ref: PixelBuf? = nil
	@State var refName: String = ""
	@State var refMode: Int = 1
	@State var refOpacity: Double = 0.45
	@State var panel: Int = 0
	@State var note: String = ""
	@State var codeText: String = ""
	@State var libName: String = ""
	@State var library: [SpriteProject] = []
	// brushes, opacity, shapes, shading
	@State var brushSize: Int = 1
	@State var brushRound: Bool = false
	@State var perfect: Bool = true
	@State var filled: Bool = false
	@State var opacity: Double = 1.0
	@State var blend: Bool = true
	@State var darken: Bool = true
	@State var stroke: [StrokeCell] = []
	/// pixels already painted this stroke (each once: lingering does not pile up see-through paint)
	@State var touched: Set<Int> = []
	// selections
	@State var sel: SpriteSel? = nil
	@State var floating: ModPixels? = nil
	@State var floatX: Int = 0
	@State var floatY: Int = 0
	@State var moveFrom: (Int, Int)? = nil
	// palettes
	@State var paletteIx: Int = 0
	@State var mine: [UInt32] = SpritePalettes.loadMine()
	@State var removing: Bool = false

	/// what COPY in a selection keeps, shared by every picture (copy from one, paste into another)
	static var clip: ModPixels? = nil

	var current: SpriteTool { return SpriteTool(rawValue: tool) ?? .pen }

	/// pixels per picture pixel on screen
	var cell: CGFloat {
		let fit: CGFloat = max(3, floor(maxSide / CGFloat(max(pixels.w, pixels.h))))
		return zoom > 0 ? zoom : fit
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .top, spacing: 12) {
				VStack(alignment: .leading, spacing: 6) {
					viewport
					zoomBar
				}
				VStack(alignment: .leading, spacing: 6) {
					toolGrid
					editButtons
					previewBox
					if refMode == 1, let r = ref { refBeside(r) }
				}
			}
			toolOptions
			if sel != nil { selectionBar }
			palette
			if showMixer { mixer }
			panelTabs
			panelBody
			if !note.isEmpty { Text(verbatim: note).font(.pixel(11, .semibold)).foregroundColor(ModUI.gold) }
		}
	}

	// MARK: canvas

	var viewW: CGFloat { return min(maxSide, cell * CGFloat(pixels.w)) }
	var viewH: CGFloat { return min(maxSide, cell * CGFloat(pixels.h)) }

	var viewport: some View {
		let c: CGFloat = cell
		let px: ModPixels = pixels
		let under: PixelBuf? = refMode == 2 ? ref : nil
		let op: Double = refOpacity
		let onionFrame: ModPixels? = (onion && frameIndex > 0 && frameIndex - 1 < frames.count) ? frames[frameIndex - 1] : nil
		let grid: Bool = showGrid
		let ox: CGFloat = panX
		let oy: CGFloat = panY
		let preview: [(Int, Int)] = shapePreview
		let col: UInt32 = SpritePaint.penColor(color, opacity)
		let s: SpriteSel? = sel
		let fl: ModPixels? = floating
		let fx: Int = floatX
		let fy: Int = floatY
		return Canvas { ctx, size in
			PixelEditorView.paintCanvas(&ctx, px, c, ox, oy, under, op, onionFrame, grid)
			PixelEditorView.paintOverlay(&ctx, c, ox, oy, preview, col, s, fl, fx, fy)
		}
		.frame(width: viewW, height: viewH)
		.clipped()
		.overlay(Rectangle().stroke(Color.white.opacity(0.35), lineWidth: 1))
		.contentShape(Rectangle())
		.gesture(DragGesture(minimumDistance: 0).onChanged { v in dragged(v.startLocation, v.location) }.onEnded { v in ended(v.location) })
	}

	/// the cells of the line, box or circle being drawn
	var shapePreview: [(Int, Int)] {
		guard let a = shapeA, let b = shapeB, current.shape else { return [] }
		return shapeCells(a, b)
	}

	func shapeCells(_ a: (Int, Int), _ b: (Int, Int)) -> [(Int, Int)] {
		switch current {
		case .line: return PixelEditorView.lineCells(a, b)
		case .box: return SpritePaint.boxCells(a, b, filled)
		default: return SpritePaint.ellipseCells(a, b, filled)
		}
	}

	static func paintCanvas(_ ctx: inout GraphicsContext, _ px: ModPixels, _ c: CGFloat, _ ox: CGFloat, _ oy: CGFloat, _ under: PixelBuf?, _ op: Double, _ onionFrame: ModPixels?, _ grid: Bool) {
		let w: Int = px.w
		let h: Int = px.h
		for y in 0..<h {
			for x in 0..<w {
				let r: CGRect = CGRect(x: CGFloat(x) * c - ox, y: CGFloat(y) * c - oy, width: c, height: c)
				let checker: Bool = (x + y) % 2 == 0
				ctx.fill(Path(r), with: .color(Color(hex: checker ? 0x3A3A3A : 0x2A2A2A)))
			}
		}
		if let u = under {
			// the reference, stretched to the canvas, under the drawing
			for y in 0..<h {
				for x in 0..<w {
					let sx: Int = min(u.w - 1, x * u.w / max(1, w))
					let sy: Int = min(u.h - 1, y * u.h / max(1, h))
					let v: UInt32 = u.px[sy * u.w + sx]
					if (v >> 24) == 0 { continue }
					let r: CGRect = CGRect(x: CGFloat(x) * c - ox, y: CGFloat(y) * c - oy, width: c, height: c)
					ctx.fill(Path(r), with: .color(Color(hex: v & 0xFFFFFF).opacity(op)))
				}
			}
		}
		if let f = onionFrame {
			for y in 0..<min(h, f.h) {
				for x in 0..<min(w, f.w) {
					let v: UInt32 = f.argb(x, y)
					if (v >> 24) == 0 { continue }
					let r: CGRect = CGRect(x: CGFloat(x) * c - ox, y: CGFloat(y) * c - oy, width: c, height: c)
					ctx.fill(Path(r), with: .color(Color(hex: v & 0xFFFFFF).opacity(0.25)))
				}
			}
		}
		for y in 0..<h {
			for x in 0..<w {
				let v: UInt32 = px.argb(x, y)
				if (v >> 24) == 0 { continue }
				let r: CGRect = CGRect(x: CGFloat(x) * c - ox, y: CGFloat(y) * c - oy, width: c, height: c)
				let a: Double = Double(v >> 24) / 255.0
				ctx.fill(Path(r), with: .color(Color(hex: v & 0xFFFFFF).opacity(a)))
			}
		}
		if grid && c >= 8 {
			for x in 0...w {
				var p = Path()
				p.move(to: CGPoint(x: CGFloat(x) * c - ox, y: -oy))
				p.addLine(to: CGPoint(x: CGFloat(x) * c - ox, y: CGFloat(h) * c - oy))
				ctx.stroke(p, with: .color(Color.white.opacity(x % 8 == 0 ? 0.25 : 0.1)), lineWidth: 1)
			}
			for y in 0...h {
				var p = Path()
				p.move(to: CGPoint(x: -ox, y: CGFloat(y) * c - oy))
				p.addLine(to: CGPoint(x: CGFloat(w) * c - ox, y: CGFloat(y) * c - oy))
				ctx.stroke(p, with: .color(Color.white.opacity(y % 8 == 0 ? 0.25 : 0.1)), lineWidth: 1)
			}
		}
	}

	/// The shape being drawn, the lifted pixels of a selection being moved, and the selection's edge
	static func paintOverlay(_ ctx: inout GraphicsContext, _ c: CGFloat, _ ox: CGFloat, _ oy: CGFloat, _ preview: [(Int, Int)], _ col: UInt32, _ s: SpriteSel?, _ fl: ModPixels?, _ fx: Int, _ fy: Int) {
		let a: Double = Double(col >> 24) / 255.0 * 0.85
		for (x, y) in preview {
			let r: CGRect = CGRect(x: CGFloat(x) * c - ox, y: CGFloat(y) * c - oy, width: c, height: c)
			ctx.fill(Path(r), with: .color(Color(hex: col & 0xFFFFFF).opacity(a)))
		}
		if let f = fl {
			for y in 0..<f.h {
				for x in 0..<f.w {
					let v: UInt32 = f.argb(x, y)
					if v == 0 { continue }
					let r: CGRect = CGRect(x: CGFloat(fx + x) * c - ox, y: CGFloat(fy + y) * c - oy, width: c, height: c)
					ctx.fill(Path(r), with: .color(Color(hex: v & 0xFFFFFF).opacity(Double(v >> 24) / 255.0)))
				}
			}
		}
		if let s0 = s {
			let r: CGRect = CGRect(x: CGFloat(s0.x0) * c - ox, y: CGFloat(s0.y0) * c - oy, width: CGFloat(s0.w) * c, height: CGFloat(s0.h) * c)
			ctx.stroke(Path(r), with: .color(Color.black), lineWidth: 3)
			ctx.stroke(Path(r), with: .color(Color.white), lineWidth: 1)
		}
	}

	func cellAt(_ p: CGPoint) -> (Int, Int)? {
		let c: CGFloat = cell
		let x: Int = Int(floor((p.x + panX) / c))
		let y: Int = Int(floor((p.y + panY) / c))
		if x < 0 || y < 0 || x >= pixels.w || y >= pixels.h { return nil }
		return (x, y)
	}

	/// the cell under the finger, kept inside the picture (for selections dragged past the edge)
	func cellClamped(_ p: CGPoint) -> (Int, Int) {
		let c: CGFloat = cell
		let x: Int = clampI(Int(floor((p.x + panX) / c)), 0, pixels.w - 1)
		let y: Int = clampI(Int(floor((p.y + panY) / c)), 0, pixels.h - 1)
		return (x, y)
	}

	func remember() {
		undo.append(pixels)
		if undo.count > 80 { undo.removeFirst() }
		redo.removeAll()
	}

	// MARK: drawing with the finger

	func dragged(_ start: CGPoint, _ p: CGPoint) {
		switch current {
		case .pan:
			panDrag(start, p)
		case .select:
			selectDrag(start, p)
		case .line, .box, .circle:
			guard let xy = cellAt(p) else { return }
			if shapeA == nil, let s = cellAt(start) { shapeA = s }
			shapeB = xy
		case .fill, .pick:
			guard let xy = cellAt(p), !stroking else { return }
			stroking = true
			if current == .pick {
				let picked: UInt32 = pixels.argb(xy.0, xy.1)
				if (picked >> 24) != 0 { pickColor(picked) }
				tool = SpriteTool.pen.rawValue
				return
			}
			remember()
			var px: ModPixels = pixels
			PixelEditorView.floodFill(&px, xy.0, xy.1, SpritePaint.penColor(color, opacity))
			pixels = px
			useColor(color)
		default:
			guard let xy = cellAt(p) else { return }
			brushDrag(xy)
		}
	}

	func panDrag(_ start: CGPoint, _ p: CGPoint) {
		if !stroking {
			stroking = true
			panStart = CGPoint(x: panX, y: panY)
		}
		let maxX: CGFloat = max(0, cell * CGFloat(pixels.w) - viewW)
		let maxY: CGFloat = max(0, cell * CGFloat(pixels.h) - viewH)
		panX = min(maxX, max(0, panStart.x - (p.x - start.x)))
		panY = min(maxY, max(0, panStart.y - (p.y - start.y)))
	}

	/// The brush tools: each pixel the finger crosses (fast strokes are joined up), the brush laid
	/// around it, the mirror copy too
	func brushDrag(_ xy: (Int, Int)) {
		let idx: Int = xy.1 * pixels.w + xy.0
		if !stroking {
			stroking = true
			remember()
			stroke = []
			touched = []
			lastXY = nil
		} else if idx == lastCell {
			return
		}
		lastCell = idx
		var px: ModPixels = pixels
		let path: [(Int, Int)] = lastXY.map { PixelEditorView.lineCells($0, xy).dropFirst().map { $0 } } ?? [xy]
		for (x, y) in path { brushAt(&px, x, y) }
		lastXY = xy
		pixels = px
		if current == .pen || current == .dither { useColor(color) }
	}

	func brushAt(_ px: inout ModPixels, _ x: Int, _ y: Int) {
		let t: SpriteTool = current
		let col: UInt32 = SpritePaint.penColor(color, opacity)
		let single: Bool = t == .pen && brushSize == 1 && perfect && !mirror
		// pixel-perfect: a one-pixel pen stroke never leaves L-shaped corners
		if single && SpritePaint.perfectCorner(stroke, x, y) {
			let b: StrokeCell = stroke.removeLast()
			px.setARGB(b.x, b.y, b.before)
			touched.remove(b.y * px.w + b.x)
		}
		var cells: [(Int, Int)] = SpritePaint.brushCells(x, y, brushSize, brushRound)
		if mirror { cells += cells.map { (px.w - 1 - $0.0, $0.1) } }
		for (cx, cy) in cells {
			if cx < 0 || cy < 0 || cx >= px.w || cy >= px.h { continue }
			let k: Int = cy * px.w + cx
			if touched.contains(k) { continue }
			touched.insert(k)
			let before: UInt32 = px.argb(cx, cy)
			switch t {
			case .erase: SpritePaint.erase(&px, cx, cy, opacity)
			case .shade: SpritePaint.shade(&px, cx, cy, darken)
			case .dither: if (cx + cy) % 2 == 0 { SpritePaint.paint(&px, cx, cy, col, blend) }
			default: SpritePaint.paint(&px, cx, cy, col, blend)
			}
			if single && cx == x && cy == y { stroke.append(StrokeCell(x: cx, y: cy, before: before)) }
		}
	}

	func ended(_ p: CGPoint) {
		if current.shape, let a = shapeA {
			let b: (Int, Int) = cellAt(p) ?? shapeB ?? a
			remember()
			var px: ModPixels = pixels
			let col: UInt32 = SpritePaint.penColor(color, opacity)
			for (x, y) in shapeCells(a, b) {
				SpritePaint.paint(&px, x, y, col, blend)
				if mirror { SpritePaint.paint(&px, px.w - 1 - x, y, col, blend) }
			}
			pixels = px
			useColor(color)
		}
		if current == .select { selectEnded() }
		shapeA = nil
		shapeB = nil
		stroking = false
		lastCell = -1
		lastXY = nil
		stroke = []
		touched = []
	}

	// MARK: selections

	/// Dragging inside the selection lifts its pixels and moves them; anywhere else chooses a new one
	func selectDrag(_ start: CGPoint, _ p: CGPoint) {
		let s0: (Int, Int) = cellClamped(start)
		let cur: (Int, Int) = cellClamped(p)
		if !stroking {
			stroking = true
			if let s = sel, s.contains(s0.0, s0.1) {
				if floating == nil {
					// lift the chosen pixels off the picture to move them
					remember()
					var px: ModPixels = pixels
					floating = SpritePaint.cut(px, s)
					SpritePaint.clearSel(&px, s)
					pixels = px
					floatX = s.x0
					floatY = s.y0
				}
				moveFrom = (s0.0 - floatX, s0.1 - floatY)
			} else {
				dropFloating()
				moveFrom = nil
				sel = SpriteSel.from(s0, s0)
			}
		}
		if let m = moveFrom, let f = floating {
			floatX = cur.0 - m.0
			floatY = cur.1 - m.1
			sel = SpriteSel(x0: floatX, y0: floatY, x1: floatX + f.w - 1, y1: floatY + f.h - 1)
		} else {
			sel = SpriteSel.from(s0, cur)
		}
	}

	func selectEnded() {
		if floating != nil { dropFloating() }
		moveFrom = nil
	}

	/// Puts moved pixels down where they are now
	func dropFloating() {
		guard let f = floating else { return }
		var px: ModPixels = pixels
		SpritePaint.drop(&px, f, floatX, floatY)
		pixels = px
		floating = nil
	}

	var selectionBar: some View {
		HStack(spacing: 4) {
			Text("SELECTION").font(.pixel(10)).foregroundColor(ModUI.dim)
			SmallButton(title: "COPY", color: ModUI.blue) { copySel() }
			SmallButton(title: "PASTE", color: ModUI.blue) { pasteSel() }
			SmallButton(title: "FLIP ↔") { flipSel() }
			SmallButton(title: "DELETE", color: ModUI.red) { deleteSel() }
			SmallButton(title: "DONE") { dropFloating(); sel = nil }
		}
	}

	func copySel() {
		guard let s = sel else { return }
		PixelEditorView.clip = floating ?? SpritePaint.cut(pixels, s)
		note = "Copied. PASTE puts it here or in another picture."
	}

	func pasteSel() {
		guard let c = PixelEditorView.clip else { note = "Copy a selection first."; return }
		dropFloating()
		remember()
		let ox: Int = sel?.x0 ?? 0
		let oy: Int = sel?.y0 ?? 0
		floating = c
		floatX = ox
		floatY = oy
		sel = SpriteSel(x0: ox, y0: oy, x1: ox + c.w - 1, y1: oy + c.h - 1)
		tool = SpriteTool.select.rawValue
		note = "Pasted: drag it where you want it, then DONE."
	}

	func flipSel() {
		guard let s = sel else { return }
		remember()
		if let f = floating {
			floating = f.flippedH()
			return
		}
		var px: ModPixels = pixels
		let part: ModPixels = SpritePaint.cut(px, s).flippedH()
		SpritePaint.clearSel(&px, s)
		SpritePaint.drop(&px, part, s.x0, s.y0)
		pixels = px
	}

	func deleteSel() {
		guard let s = sel else { return }
		remember()
		if floating != nil {
			floating = nil
		} else {
			var px: ModPixels = pixels
			SpritePaint.clearSel(&px, s)
			pixels = px
		}
		sel = nil
	}

	static func lineCells(_ a: (Int, Int), _ b: (Int, Int)) -> [(Int, Int)] {
		var out: [(Int, Int)] = []
		var x0: Int = a.0
		var y0: Int = a.1
		let dx: Int = abs(b.0 - x0)
		let dy: Int = -abs(b.1 - y0)
		let sx: Int = x0 < b.0 ? 1 : -1
		let sy: Int = y0 < b.1 ? 1 : -1
		var err: Int = dx + dy
		var guardN: Int = 0
		while guardN < 512 {
			guardN += 1
			out.append((x0, y0))
			if x0 == b.0 && y0 == b.1 { break }
			let e2: Int = 2 * err
			if e2 >= dy { err += dy; x0 += sx }
			if e2 <= dx { err += dx; y0 += sy }
		}
		return out
	}

	static func boxCells(_ a: (Int, Int), _ b: (Int, Int)) -> [(Int, Int)] {
		return SpritePaint.boxCells(a, b, false)
	}

	static func floodFill(_ px: inout ModPixels, _ sx: Int, _ sy: Int, _ col: UInt32) {
		let target: UInt32 = px.argb(sx, sy)
		if target == col { return }
		var stack: [(Int, Int)] = [(sx, sy)]
		var guardN: Int = 0
		while let cur = stack.popLast() {
			guardN += 1
			if guardN > 40000 { break }
			let (x, y) = cur
			if x < 0 || y < 0 || x >= px.w || y >= px.h { continue }
			if px.argb(x, y) != target { continue }
			px.setARGB(x, y, col)
			stack.append((x + 1, y))
			stack.append((x - 1, y))
			stack.append((x, y + 1))
			stack.append((x, y - 1))
		}
	}

	// MARK: tools

	var zoomBar: some View {
		HStack(spacing: 6) {
			SmallButton(title: "−") { setZoom(cell - (cell > 16 ? 8 : 2)) }
			Text(verbatim: joinText(String(Int(cell)), " px")).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			SmallButton(title: "+") { setZoom(cell + (cell >= 16 ? 8 : 2)) }
			SmallButton(title: "FIT") { zoom = 0; panX = 0; panY = 0 }
			SmallButton(title: showGrid ? "GRID ON" : "GRID OFF", color: showGrid ? ModUI.accent : Color(ui: 0x555555)) { showGrid.toggle() }
			if frameIndex > 0 {
				SmallButton(title: onion ? "ONION ON" : "ONION OFF", color: onion ? ModUI.accent : Color(ui: 0x555555)) { onion.toggle() }
			}
		}
	}

	func setZoom(_ z: CGFloat) {
		zoom = min(48, max(3, z))
		panX = 0
		panY = 0
	}

	var toolGrid: some View {
		PlainGrid(count: SpriteTool.allCases.count + 1, per: 3, spacing: 4) { (i: Int) in self.toolButton(i) }
			.frame(width: 250)
	}

	func toolButton(_ i: Int) -> some View {
		if i >= SpriteTool.allCases.count {
			return SmallButton(title: mirror ? "MIRROR ON" : "MIRROR", color: mirror ? ModUI.accent : Color(ui: 0x555555)) { mirror.toggle() }
		}
		let name: String = SpriteTool.allCases[i].name
		return SmallButton(title: name, color: tool == i ? ModUI.accent : Color(ui: 0x555555)) { selectTool(i) }
	}

	func selectTool(_ i: Int) {
		if tool == SpriteTool.select.rawValue && i != tool { dropFloating(); sel = nil }
		tool = i
	}

	/// The chosen tool's settings: brush size and shape, pixel-perfect, filled shapes, darker or lighter
	@ViewBuilder
	var toolOptions: some View {
		let t: SpriteTool = current
		if t.brush || t == .line {
			HStack(spacing: 6) {
				if t.brush {
					Text(verbatim: joinText("BRUSH ", String(brushSize))).font(.pixel(11)).foregroundColor(Color.white)
					SmallButton(title: "−") { brushSize = max(1, brushSize - 1) }
					SmallButton(title: "+") { brushSize = min(8, brushSize + 1) }
					SmallButton(title: brushRound ? "ROUND" : "SQUARE") { brushRound.toggle() }
				}
				if t == .pen && brushSize == 1 {
					SmallButton(title: perfect ? "PIXEL-PERFECT ON" : "PIXEL-PERFECT OFF", color: perfect ? ModUI.accent : Color(ui: 0x555555)) { perfect.toggle() }
				}
				if t == .shade {
					SmallButton(title: darken ? "DARKER" : "LIGHTER", color: darken ? Color(ui: 0x3A3A5A) : Color(ui: 0x8A8A5A)) { darken.toggle() }
				}
			}
		} else if t == .box || t == .circle {
			HStack(spacing: 6) {
				SmallButton(title: filled ? "FILLED" : "OUTLINE", color: filled ? ModUI.accent : Color(ui: 0x555555)) { filled.toggle() }
			}
		} else if t == .select && sel == nil {
			Text("Drag to choose pixels; drag inside the choice to move them.").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
		}
	}

	var editButtons: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 4) {
				SmallButton(title: "UNDO", color: undo.isEmpty ? Color(ui: 0x444444) : Color(ui: 0x5A5A70)) { undoStep() }
				SmallButton(title: "REDO", color: redo.isEmpty ? Color(ui: 0x444444) : Color(ui: 0x5A5A70)) { redoStep() }
				SmallButton(title: "CLEAR", color: ModUI.red) {
					remember()
					var e = ModPixels(w: pixels.w, h: pixels.h)
					e.outline = pixels.outline
					pixels = e
				}
			}
			HStack(spacing: 4) {
				SmallButton(title: "FLIP ↔") { change { $0.flippedH() } }
				SmallButton(title: "FLIP ↕") { change { $0.flippedV() } }
				if pixels.w == pixels.h { SmallButton(title: "TURN") { change { $0.rotated() } } }
			}
			HStack(spacing: 4) {
				SmallButton(title: "◀") { change { $0.shifted(-1, 0) } }
				SmallButton(title: "▶") { change { $0.shifted(1, 0) } }
				SmallButton(title: "▲") { change { $0.shifted(0, -1) } }
				SmallButton(title: "▼") { change { $0.shifted(0, 1) } }
			}
			outlineButton
		}
	}

	var outlineButton: some View {
		let on: Bool = pixels.outlined(outlineDefault)
		return SmallButton(title: on ? "OUTLINE ON" : "OUTLINE OFF", color: on ? ModUI.accent : Color(ui: 0x555555)) {
			var p: ModPixels = pixels
			p.outline = !on
			pixels = p
		}
	}

	func undoStep() {
		floating = nil
		if let last = undo.popLast() {
			redo.append(pixels)
			pixels = last
		}
	}

	func redoStep() {
		if let next = redo.popLast() {
			undo.append(pixels)
			pixels = next
		}
	}

	func change(_ f: (ModPixels) -> ModPixels) {
		dropFloating()
		remember()
		pixels = f(pixels)
	}

	/// what it looks like in the game: actual pixels, outlined or not as chosen
	var previewBox: some View {
		let on: Bool = pixels.outlined(outlineDefault)
		var b: PixelBuf = pixels.buf()
		if on {
			b = padBuf(b)
			b.outline(0x101010)
		}
		let scale: CGFloat = max(1, floor(96 / CGFloat(max(b.w, b.h))))
		return VStack(alignment: .leading, spacing: 4) {
			Text("IN THE GAME").font(.pixel(10)).foregroundColor(ModUI.dim)
			HStack(alignment: .bottom, spacing: 8) {
				pixImage(b).resizable().interpolation(.none).frame(width: CGFloat(b.w) * scale, height: CGFloat(b.h) * scale)
					.background(Color(ui: 0x6AA0D8).opacity(0.5))
				if frames.count > 1 { animation }
			}
			currentSwatch
		}
	}

	/// The colour in use, over a checker so its opacity shows
	var currentSwatch: some View {
		let a: Double = Double(SpritePaint.penColor(color, opacity) >> 24) / 255.0
		let pct: Int = Int((a * 100).rounded())
		return HStack(spacing: 6) {
			ZStack {
				HStack(spacing: 0) {
					Rectangle().fill(Color(hex: 0xC8C8C8)).frame(width: 13, height: 26)
					Rectangle().fill(Color(hex: 0x6A6A6A)).frame(width: 13, height: 26)
				}
				Rectangle().fill(Color(hex: color & 0xFFFFFF).opacity(a)).frame(width: 26, height: 26)
			}
			.overlay(Rectangle().stroke(Color.white, lineWidth: 2))
			Text(verbatim: joinText(String(pixels.w), " x ", String(pixels.h), "  ", String(pct), "%")).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
		}
	}

	/// the frames played in a loop (about six a second)
	var animation: some View {
		let fr: [ModPixels] = frames.isEmpty ? [pixels] : frames
		let i: Int = frameIndex
		let cur: ModPixels = pixels
		return TimelineView(.animation) { context in
			let n: Int = max(1, fr.count)
			let k: Int = Int(context.date.timeIntervalSinceReferenceDate * 6.0) % n
			let f: ModPixels = k == i ? cur : fr[k]
			pixImage(f.buf()).resizable().interpolation(.none).frame(width: 56, height: 56 * CGFloat(f.h) / CGFloat(max(1, f.w)))
		}
	}

	func refBeside(_ r: PixelBuf) -> some View {
		let scale: CGFloat = max(1, floor(120 / CGFloat(max(r.w, r.h))))
		return VStack(alignment: .leading, spacing: 2) {
			Text(verbatim: joinText("REFERENCE: ", refName)).font(.pixel(10)).foregroundColor(ModUI.dim).lineLimit(1)
			pixImage(r).resizable().interpolation(.none).frame(width: CGFloat(r.w) * scale, height: CGFloat(r.h) * scale)
				.background(Color.black.opacity(0.35))
		}
	}

	// MARK: colours

	var paletteColors: [UInt32] {
		if paletteIx >= SpritePalettes.sets.count { return mine }
		return SpritePalettes.sets[paletteIx]
	}

	var palette: some View {
		let cols: [UInt32] = paletteColors
		return VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 4) {
				ForEach(0..<SpritePalettes.names.count, id: \.self) { (i: Int) in self.paletteChip(i) }
			}
			if cols.isEmpty {
				Text("Your own colours go here: mix one, then SAVE COLOUR.").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			} else {
				PlainGrid(count: cols.count, per: 16, spacing: 4) { (i: Int) in self.swatch(cols[i]) }
			}
			if !recent.isEmpty {
				HStack(spacing: 4) {
					Text("RECENT").font(.pixel(9)).foregroundColor(ModUI.dim)
					ForEach(0..<recent.count, id: \.self) { (i: Int) in self.swatch(recent[i]) }
				}
			}
			HStack(spacing: 6) {
				SmallButton(title: showMixer ? "HIDE COLOUR MIXER" : "MIX A COLOUR...") { showMixer.toggle() }
				SmallButton(title: "SAVE COLOUR", color: ModUI.blue) { saveColour() }
				if paletteIx >= SpritePalettes.sets.count && !mine.isEmpty {
					SmallButton(title: removing ? "TAP ONE TO REMOVE" : "REMOVE...", color: removing ? ModUI.red : Color(ui: 0x555555)) { removing.toggle() }
				}
			}
		}
	}

	func paletteChip(_ i: Int) -> some View {
		let on: Bool = paletteIx == i
		return SmallButton(title: SpritePalettes.names[i], color: on ? ModUI.blue : Color(ui: 0x4A4A50)) {
			paletteIx = i
			removing = false
		}
	}

	func swatch(_ c0: UInt32) -> some View {
		let c: UInt32 = (c0 >> 24) == 0 ? (0xFF000000 | c0) : c0
		let on: Bool = (color & 0xFFFFFF) == (c & 0xFFFFFF)
		let a: Double = Double(c >> 24) / 255.0
		return Rectangle().fill(Color(hex: c & 0xFFFFFF).opacity(a))
			.frame(width: 30, height: 30)
			.background(Color(ui: 0x8A8A8A))
			.overlay(Rectangle().stroke(on ? Color.white : Color.black, lineWidth: on ? 3 : 1))
			.onTapGesture { self.tapSwatch(c) }
	}

	func tapSwatch(_ c: UInt32) {
		if removing {
			mine.removeAll { $0 == c }
			SpritePalettes.saveMine(mine)
			if mine.isEmpty { removing = false }
			return
		}
		pickColor(0xFF000000 | (c & 0xFFFFFF))
		if (c >> 24) < 255 { opacity = Double(c >> 24) / 255.0 }
		let t: SpriteTool = current
		if t == .erase || t == .pick || t == .pan || t == .select || t == .shade { selectTool(SpriteTool.pen.rawValue) }
	}

	func saveColour() {
		let c: UInt32 = SpritePaint.penColor(color, opacity)
		if mine.contains(c) { note = "That colour is saved already."; return }
		mine.append(c)
		if mine.count > 32 { mine.removeFirst() }
		SpritePalettes.saveMine(mine)
		paletteIx = SpritePalettes.sets.count
		note = "Saved to MINE (kept on this iPad)."
	}

	func pickColor(_ c: UInt32) {
		color = 0xFF000000 | (c & 0xFFFFFF)
		mixR = Double((c >> 16) & 0xFF)
		mixG = Double((c >> 8) & 0xFF)
		mixB = Double(c & 0xFF)
	}

	func useColor(_ c: UInt32) {
		if modPalette.contains(c & 0xFFFFFF) { return }
		recent.removeAll { $0 == c }
		recent.insert(c, at: 0)
		if recent.count > 8 { recent.removeLast() }
	}

	var mixer: some View {
		VStack(spacing: 4) {
			StatSlider(label: "Red", value: mixBind(0), range: 0...255, step: 1, format: "%.0f")
			StatSlider(label: "Green", value: mixBind(1), range: 0...255, step: 1, format: "%.0f")
			StatSlider(label: "Blue", value: mixBind(2), range: 0...255, step: 1, format: "%.0f")
			StatSlider(label: "Opacity (pen)", value: $opacity, range: 0.05...1.0, step: 0.05, format: "%.2f")
			HStack(spacing: 6) {
				SmallButton(title: blend ? "BLEND ON" : "BLEND OFF", color: blend ? ModUI.accent : Color(ui: 0x555555)) { blend.toggle() }
				Text(verbatim: blend ? "See-through paint mixes with what is under it." : "See-through paint makes see-through pixels.").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
		}
	}

	func mixBind(_ k: Int) -> Binding<Double> {
		return Binding<Double>(get: {
			k == 0 ? mixR : (k == 1 ? mixG : mixB)
		}, set: { v in
			if k == 0 { mixR = v } else if k == 1 { mixG = v } else { mixB = v }
			let r: UInt32 = UInt32(clampD(mixR, 0, 255))
			let g: UInt32 = UInt32(clampD(mixG, 0, 255))
			let b: UInt32 = UInt32(clampD(mixB, 0, 255))
			color = 0xFF000000 | (r << 16) | (g << 8) | b
			let t: SpriteTool = current
			if !(t == .pen || t == .fill || t.shape || t == .dither) { selectTool(SpriteTool.pen.rawValue) }
		})
	}

	// MARK: panels: reference, size, copy in and out, library

	var panelTabs: some View {
		HStack(spacing: 6) {
			ForEach(0..<4, id: \.self) { i in
				SmallButton(title: ["REFERENCE", "SIZE", "COPY & PASTE", "SPRITE LIBRARY"][i], color: panel == i + 1 ? ModUI.blue : Color(ui: 0x4A4A50)) {
					panel = panel == i + 1 ? 0 : i + 1
					if panel == 4 { library = SpriteLibrary.load() }
				}
			}
		}
	}

	@ViewBuilder
	var panelBody: some View {
		switch panel {
		case 1: referencePanel
		case 2: sizePanel
		case 3: copyPanel
		case 4: libraryPanel
		default: EmptyView()
		}
	}

	var referencePanel: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Pick any picture from the game, your library or the clipboard. Show it beside the canvas or under it as a guide, or copy it in as a starting sample (the original never changes).")
				.font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			if ref != nil {
				HStack(spacing: 6) {
					SmallButton(title: "BESIDE", color: refMode == 1 ? ModUI.accent : Color(ui: 0x555555)) { refMode = 1 }
					SmallButton(title: "UNDER", color: refMode == 2 ? ModUI.accent : Color(ui: 0x555555)) { refMode = 2 }
					SmallButton(title: "HIDE", color: refMode == 0 ? ModUI.accent : Color(ui: 0x555555)) { refMode = 0 }
					SmallButton(title: "USE AS SAMPLE", color: ModUI.blue) { useSample() }
					SmallButton(title: "REMOVE", color: ModUI.red) { ref = nil; refName = "" }
				}
				if refMode == 2 { StatSlider(label: "See-through", value: $refOpacity, range: 0.1...0.9, step: 0.05, format: "%.2f") }
			}
			SpriteRefPicker(pick: { b, name in
				ref = b
				refName = name
				if refMode == 0 { refMode = 1 }
				note = joinText("Reference: ", name, ".")
			}, pasteNote: { note = $0 }, size: (pixels.w, pixels.h))
		}
	}

	/// Copies the reference into the canvas as a starting point (fitted to the canvas, or the canvas
	/// sized to it where that is allowed)
	func useSample() {
		guard let r = ref else { return }
		remember()
		var p: ModPixels
		if !sizes.isEmpty && onResize == nil && r.w <= 64 && r.h <= 64 && (sizes.contains(r.w) && sizes.contains(r.h)) {
			p = ModPixels(buf: r)
		} else {
			p = ModPixels.fitted(r, pixels.w, pixels.h)
		}
		p.outline = pixels.outline
		pixels = p
		note = joinText("Copied ", refName, " in to start from. The original is unchanged.")
	}

	var sizePanel: some View {
		VStack(alignment: .leading, spacing: 6) {
			if sizes.isEmpty {
				Text(verbatim: joinText("This picture is always ", String(pixels.w), " x ", String(pixels.h), ".")).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			} else {
				Text("New size (KEEP keeps the picture as it is, centred at the bottom; STRETCH scales it)").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
				ForEach(sizes, id: \.self) { sz in
					HStack(spacing: 6) {
						Text(verbatim: joinText(String(sz), " x ", String(sz))).font(.pixel(11)).foregroundColor(Color.white).frame(width: 70, alignment: .leading)
						SmallButton(title: "KEEP") { resize(sz, sz, false) }
						SmallButton(title: "STRETCH") { resize(sz, sz, true) }
						if sz != pixels.h && pixels.w != sz {
							SmallButton(title: joinText(String(sz), " x ", String(pixels.h))) { resize(sz, pixels.h, false) }
						}
					}
				}
			}
		}
	}

	func resize(_ w: Int, _ h: Int, _ stretch: Bool) {
		if let f = onResize {
			f(w, h)
			return
		}
		remember()
		var p: ModPixels = stretch ? pixels.scaled(w, h) : pixels.resized(w, h)
		p.outline = pixels.outline
		pixels = p
		zoom = 0
		panX = 0
		panY = 0
	}

	var copyPanel: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("A sprite code copies a picture exactly (paste it into another mod, or send it to a friend). A picture copied from Photos or a drawing app is shrunk to this size.")
				.font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			HStack(spacing: 6) {
				SmallButton(title: "COPY CODE", color: ModUI.blue) {
					SpriteClipboard.copy(pixels)
					codeText = pixels.spriteCode()
					note = "The sprite code is on the clipboard."
				}
				SmallButton(title: "PASTE CODE", color: ModUI.blue) {
					if let p = SpriteClipboard.pasteCode() ?? ModPixels.fromSpriteCode(codeText) { pasteIn(p) } else { note = "No sprite code on the clipboard (or in the box below)." }
				}
				SmallButton(title: "PASTE PICTURE", color: ModUI.blue) {
					if let p = SpriteClipboard.pasteImage(pixels.w, pixels.h) { pasteIn(p) } else { note = "No picture on the clipboard: copy one first." }
				}
			}
			ModTextField(label: "Sprite code", text: $codeText, placeholder: "PRSPR1:...")
		}
	}

	func pasteIn(_ p0: ModPixels) {
		remember()
		var p: ModPixels = p0
		if p.w != pixels.w || p.h != pixels.h {
			if sizes.contains(p.w) && sizes.contains(p.h) && onResize == nil {
				// fits a size this picture may take: keep it as it is
			} else {
				p = ModPixels.fitted(p0.buf(), pixels.w, pixels.h)
				p.outline = p0.outline
			}
		}
		pixels = p
		note = "Pasted."
	}

	var libraryPanel: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 6) {
				ModTextField(label: "Save as", text: $libName, placeholder: "My sprite")
				SmallButton(title: "SAVE TO LIBRARY", color: ModUI.accent) {
					var pr = SpriteProject()
					pr.name = libName.isEmpty ? "Sprite" : libName
					pr.frames = frames.count > 1 ? frames.enumerated().map { $0.offset == frameIndex ? pixels : $0.element } : [pixels]
					let saved: SpriteProject = SpriteLibrary.put(pr)
					library = SpriteLibrary.load()
					note = joinText("Saved ", saved.name, " to the library.")
				}
			}
			if library.isEmpty { Text("The library is empty.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim) }
			ForEach(library) { pr in
				HStack(spacing: 8) {
					pixImage(pr.frames[0].buf()).resizable().interpolation(.none).frame(width: 36, height: 36).background(Color.black.opacity(0.35))
					VStack(alignment: .leading, spacing: 1) {
						Text(verbatim: pr.name).font(.pixel(12)).foregroundColor(Color.white)
						Text(verbatim: joinText(String(pr.frames[0].w), " x ", String(pr.frames[0].h), pr.frames.count > 1 ? joinText(" · ", String(pr.frames.count), " frames") : "")).font(.pixel(9, .semibold)).foregroundColor(ModUI.dim)
					}
					Spacer()
					SmallButton(title: "OPEN") { pasteIn(pr.frames[min(frameIndex, pr.frames.count - 1)]) }
					SmallButton(title: "REFERENCE") {
						ref = pr.frames[0].buf()
						refName = pr.name
						if refMode == 0 { refMode = 1 }
					}
					SmallButton(title: "✕", color: ModUI.red) {
						SpriteLibrary.delete(pr.id)
						library = SpriteLibrary.load()
					}
				}
			}
		}
	}
}

/// Choosing a reference picture: a game creature (any of its frames), item or block, a sprite from
/// the library, or a picture from the clipboard
struct SpriteRefPicker: View {
	var pick: (PixelBuf, String) -> Void
	var pasteNote: (String) -> Void
	var size: (Int, Int)
	@State var tab: Int = 0
	@State var filter: String = ""
	@State var creature: Int = -1

	static let tabNames: [String] = ["CREATURES", "ITEMS", "BLOCKS", "LIBRARY"]

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			tabRow
			ModTextField(label: "Search", text: $filter, placeholder: "name")
			grid
		}
		.padding(8)
		.background(Color.black.opacity(0.25))
	}

	var tabRow: some View {
		HStack(spacing: 6) {
			ForEach(0..<4, id: \.self) { i in self.tabButton(i) }
			SmallButton(title: "PASTE PICTURE", color: ModUI.blue) { self.paste() }
		}
	}

	func tabButton(_ i: Int) -> some View {
		let col: Color = tab == i ? ModUI.accent : Color(ui: 0x555555)
		return SmallButton(title: SpriteRefPicker.tabNames[i], color: col) {
			self.tab = i
			self.creature = -1
		}
	}

	func paste() {
		let w: Int = min(64, max(16, size.0 * 2))
		let h: Int = min(64, max(16, size.1 * 2))
		if let p = SpriteClipboard.pasteImage(w, h) {
			pick(p.buf(), "Pasted picture")
		} else if let p = SpriteClipboard.pasteCode() {
			pick(p.buf(), "Pasted sprite")
		} else {
			pasteNote("No picture on the clipboard: copy one first.")
		}
	}

	/// A picture to offer: what it shows, its name, and the creature it opens (-1: it is picked)
	struct RefEntry {
		let buf: PixelBuf
		let name: String
		let opens: Int
	}

	/// What the chosen tab offers
	var entries: [RefEntry] {
		var out: [RefEntry] = []
		switch tab {
		case 0:
			if creature >= 0, let k = MobKind(rawValue: creature) {
				let frs: [PixelBuf] = GameSprites.creatureFrames(k)
				let name: String = mobDef(k).name
				for (i, f) in frs.enumerated() { out.append(RefEntry(buf: f, name: joinText(name, " ", String(i + 1)), opens: -1)) }
			} else {
				for k in GameSprites.creatures where match(mobDef(k).name) {
					let f: PixelBuf = GameSprites.creatureFrames(k).first ?? PixelBuf(w: 1, h: 1)
					out.append(RefEntry(buf: f, name: mobDef(k).name, opens: k.rawValue))
				}
			}
		case 1:
			for it in GameSprites.items() where match(it.name) { out.append(RefEntry(buf: itemBuf(it), name: it.name, opens: -1)) }
		case 2:
			for t in GameSprites.tiles() where match(t.name) { out.append(RefEntry(buf: tileBuf(t), name: t.name, opens: -1)) }
		default:
			for pr in SpriteLibrary.load() where match(pr.name) { out.append(RefEntry(buf: pr.frames[0].buf(), name: pr.name, opens: -1)) }
		}
		return out
	}

	var grid: some View {
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 64), spacing: 6)]
		let list: [RefEntry] = entries
		return LazyVGrid(columns: cols, spacing: 6) {
			ForEach(0..<list.count, id: \.self) { i in self.entryCell(list[i]) }
		}
	}

	func entryCell(_ e: RefEntry) -> some View {
		Button(action: { self.tapped(e) }) { self.label(e.buf, e.name) }.buttonStyle(.plain)
	}

	func tapped(_ e: RefEntry) {
		if e.opens >= 0 { creature = e.opens } else { pick(e.buf, e.name) }
	}

	func match(_ n: String) -> Bool {
		let f: String = filter.trimmingCharacters(in: .whitespaces).lowercased()
		return f.isEmpty || n.lowercased().contains(f)
	}

	func cell(_ b: PixelBuf, _ name: String) -> some View {
		Button { pick(b, name) } label: { label(b, name) }.buttonStyle(.plain)
	}

	func label(_ b: PixelBuf, _ name: String) -> some View {
		VStack(spacing: 2) {
			pixImage(b).resizable().interpolation(.none).frame(width: 40, height: 40 * CGFloat(b.h) / CGFloat(max(1, b.w)))
				.frame(height: 44)
			Text(verbatim: name).font(.pixel(8, .semibold)).foregroundColor(Color.white).lineLimit(1)
		}
		.frame(maxWidth: .infinity, minHeight: 64)
		.background(ModUI.card)
	}
}

/// The sprite library on its own: every saved sprite, to make, open, copy, rename and delete
struct SpriteLibraryScreen: View {
	var back: () -> Void
	@State var list: [SpriteProject] = []
	@State var editing: SpriteProject? = nil
	@State var frame: Int = 0
	@State var loaded: Bool = false

	static let sizes: [Int] = [8, 16, 24, 32]

	var body: some View {
		VStack(spacing: 10) {
			topBar
			ScrollView {
				VStack(spacing: 10) {
					if editing != nil { editor } else { listPage }
				}
				.padding(.bottom, 30)
			}
		}
		.padding(14)
		.frame(maxWidth: 1000)
		.onAppear { self.load() }
	}

	/// Stays at the top while the page scrolls, so there is always a way back
	var topBar: some View {
		HStack(spacing: 8) {
			if editing != nil {
				SmallButton(title: "< LIBRARY", color: ModUI.blue) { self.done() }
				SmallButton(title: "SAVE", color: ModUI.accent) { self.save() }
			} else {
				SmallButton(title: "< MODS") { self.back() }
			}
			Spacer()
			Text("SPRITE LIBRARY").font(.pixel(22)).foregroundColor(ModUI.gold)
			Spacer()
		}
	}

	func load() {
		if loaded { return }
		loaded = true
		list = SpriteLibrary.load()
	}

	var listPage: some View {
		VStack(spacing: 10) {
			Text("Sprites kept here belong to no mod: finish them later, use them as references, or copy them into any mod's content.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			HStack(spacing: 6) {
				ForEach(SpriteLibraryScreen.sizes, id: \.self) { sz in self.newButton(sz) }
			}
			VStack(spacing: 6) {
				ForEach(list) { pr in self.row(pr) }
			}
		}
	}

	func newButton(_ sz: Int) -> some View {
		let title: String = joinText("+ NEW ", String(sz), " x ", String(sz))
		return PixelButton(title: title, color: ModUI.accent) { self.makeNew(sz) }
	}

	func makeNew(_ sz: Int) {
		var p = SpriteProject()
		p.name = joinText("Sprite ", String(list.count + 1))
		p.frames = [ModPixels(w: sz, h: sz)]
		editing = SpriteLibrary.put(p)
		frame = 0
	}

	func row(_ pr: SpriteProject) -> some View {
		let f0: ModPixels = pr.frames[0]
		let frames: String = pr.frames.count == 1 ? " frame \u{00B7} " : " frames \u{00B7} "
		let line: String = joinText(String(f0.w), " x ", String(f0.h), " \u{00B7} ", String(pr.frames.count), frames, shortDate(pr.edited))
		let img: Image = pixImage(f0.buf())
		return HStack(spacing: 8) {
			img.resizable().interpolation(.none).frame(width: 44, height: 44).background(Color.black.opacity(0.35))
			VStack(alignment: .leading, spacing: 1) {
				Text(verbatim: pr.name).font(.pixel(13)).foregroundColor(Color.white)
				Text(verbatim: line).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer()
			SmallButton(title: "EDIT", color: ModUI.blue) { self.open(pr) }
			SmallButton(title: "COPY") { self.copy(pr) }
			SmallButton(title: "\u{2715}", color: ModUI.red) { self.delete(pr) }
		}
		.padding(6)
		.background(PixelBox(color: ModUI.card))
	}

	func open(_ pr: SpriteProject) {
		editing = pr
		frame = 0
	}

	func copy(_ pr: SpriteProject) {
		_ = SpriteLibrary.duplicate(pr.id)
		list = SpriteLibrary.load()
	}

	func delete(_ pr: SpriteProject) {
		SpriteLibrary.delete(pr.id)
		list = SpriteLibrary.load()
	}

	var nameBind: Binding<String> {
		return Binding<String>(get: { self.editing?.name ?? "" }, set: { (v: String) in self.editing?.name = v })
	}

	var pixBind: Binding<ModPixels> {
		return Binding<ModPixels>(get: { self.currentFrame() }, set: { (v: ModPixels) in self.setFrame(v) })
	}

	func currentFrame() -> ModPixels {
		guard let e = editing, frame < e.frames.count else { return ModPixels(w: 16, h: 16) }
		return e.frames[frame]
	}

	func setFrame(_ v: ModPixels) {
		guard var e = editing, frame < e.frames.count else { return }
		e.frames[frame] = v
		editing = e
	}

	var editor: some View {
		let pr: SpriteProject = editing ?? SpriteProject()
		return VStack(alignment: .leading, spacing: 8) {
			ModTextField(label: "Name", text: nameBind, placeholder: "Sprite")
			frameRow(pr.frames.count)
			PixelEditorView(pixels: pixBind, maxSide: 420, frames: pr.frames, frameIndex: frame, sizes: [8, 12, 16, 24, 32, 48, 64], outlineDefault: true,
							onResize: { (w: Int, h: Int) in self.resizeAll(w, h) })
		}
	}

	func frameRow(_ count: Int) -> some View {
		let canAdd: Bool = count < ModLimits.maxFrames
		let canDelete: Bool = count > 1
		return HStack(spacing: 6) {
			ForEach(0..<count, id: \.self) { i in self.frameButton(i) }
			if canAdd { SmallButton(title: "+ FRAME", color: ModUI.blue) { self.addFrame() } }
			if canDelete { SmallButton(title: "DELETE FRAME", color: ModUI.red) { self.deleteFrame() } }
		}
	}

	func frameButton(_ i: Int) -> some View {
		let col: Color = frame == i ? ModUI.accent : Color(ui: 0x555555)
		return SmallButton(title: joinText("FRAME ", String(i + 1)), color: col) { self.frame = i }
	}

	func addFrame() {
		guard var e = editing else { return }
		e.frames.append(e.frames[min(frame, e.frames.count - 1)])
		editing = e
		frame = e.frames.count - 1
	}

	func deleteFrame() {
		guard var e = editing, e.frames.count > 1 else { return }
		e.frames.remove(at: min(frame, e.frames.count - 1))
		editing = e
		frame = max(0, min(frame, e.frames.count - 1))
	}

	func resizeAll(_ w: Int, _ h: Int) {
		guard var e = editing else { return }
		e.frames = e.frames.map { $0.resized(w, h) }
		editing = e
	}

	func done() {
		save()
		editing = nil
	}

	func save() {
		guard let e = editing else { return }
		editing = SpriteLibrary.put(e)
		list = SpriteLibrary.load()
	}
}

// MARK: - Mod Creator+: the infusion editor

/// The INFUSIONS tab: the mod's own infusions
struct InfusionListView: View {
	@ObservedObject var s: ModSession
	var open: (String) -> Void

	var body: some View {
		VStack(spacing: 8) {
			Text("Infusions are worked into equipment at an Infusion Crucible. Each one has a compound: make a recipe for it so players can craft it.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			PixelButton(title: "+ NEW INFUSION", color: ModUI.accent) { self.makeNew() }
			ForEach(s.mod.infusions) { f in self.row(f) }
		}
	}

	func makeNew() {
		var f = ModInfusion()
		f.id = s.mod.freshID("f")
		f.name = joinText("Infusion ", String(s.mod.infusions.count + 1))
		f.damagePct = 10
		s.mod.infusions.append(f)
		s.touch()
		open(f.id)
	}

	func row(_ f: ModInfusion) -> some View {
		let img: Image = pixImage(ModRuntime.shared.compoundIcon(f))
		let isOff: Bool = s.mod.off.contains(f.id)
		let fid: String = f.id
		return ModRow(image: img, title: f.name, sub: f.blurb, open: { self.open(fid) }, copy: { self.copy(f) },
					  delete: { self.delete(fid) }, off: isOff, toggle: { self.toggle(fid) })
	}

	func copy(_ f: ModInfusion) {
		var c: ModInfusion = f
		c.id = s.mod.freshID("f")
		c.name = String(joinText(f.name, " copy").prefix(32))
		s.mod.infusions.append(c)
		s.touch()
	}

	func delete(_ fid: String) {
		s.mod.infusions.removeAll { $0.id == fid }
		s.touch()
	}

	func toggle(_ fid: String) {
		if s.mod.off.contains(fid) { s.mod.off.removeAll { $0 == fid } } else { s.mod.off.append(fid) }
		s.touch()
	}
}

/// Editing one custom infusion
/// A slider of an editor, as data: its label, the number it changes, its range (and the top in sandbox
/// mode), its step and how it is shown. Editors with many numbers list them like this, which keeps them
/// quick for the compiler (one row type instead of a long chain of views).
struct DSlider<Root> {
	let label: String
	let kp: WritableKeyPath<Root, Double>
	let lo: Double
	let hi: Double
	let sbHi: Double
	let step: Double
	let format: String
}

/// A before-and-after line of a preview
struct PreviewRow: View {
	let name: String
	let before: String
	let after: String
	var body: some View {
		let changed: Bool = before != after
		let col: Color = changed ? Color(ui: 0x7AF08A) : Color.white
		return HStack {
			Text(verbatim: name).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			Spacer()
			Text(verbatim: before).font(.pixel(11)).foregroundColor(Color.white.opacity(0.7))
			Text("\u{2192}").font(.pixel(11)).foregroundColor(ModUI.dim)
			Text(verbatim: after).font(.pixel(11)).foregroundColor(col)
		}
	}
}

struct InfusionEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	var openRecipe: (String) -> Void
	@State var pickingItem: Bool = false

	func b<T>(_ kp: WritableKeyPath<ModInfusion, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.infusions, id, kp, d) }
	var inf: ModInfusion { return s.mod.infusions.first { $0.id == id } ?? ModInfusion() }

	static let numbers: [DSlider<ModInfusion>] = [
		DSlider(label: "Damage %", kp: \.damagePct, lo: -50, hi: 100, sbHi: 400, step: 1, format: "%.0f"),
		DSlider(label: "Extra damage", kp: \.damageFlat, lo: 0, hi: 20, sbHi: 100, step: 0.5, format: "%.1f"),
		DSlider(label: "Attack speed %", kp: \.attackSpeedPct, lo: -50, hi: 60, sbHi: 60, step: 1, format: "%.0f"),
		DSlider(label: "Extra reach", kp: \.reach, lo: 0, hi: 1.5, sbHi: 4, step: 0.1, format: "%.1f"),
		DSlider(label: "Critical chance %", kp: \.critPct, lo: 0, hi: 40, sbHi: 100, step: 1, format: "%.0f"),
		DSlider(label: "Knockback %", kp: \.knockPct, lo: -80, hi: 100, sbHi: 400, step: 1, format: "%.0f"),
		DSlider(label: "Mining speed %", kp: \.miningPct, lo: 0, hi: 100, sbHi: 400, step: 1, format: "%.0f"),
		DSlider(label: "Defence (armour)", kp: \.defense, lo: 0, hi: 4, sbHi: 20, step: 0.1, format: "%.1f"),
		DSlider(label: "Run speed % (armour)", kp: \.moveSpeedPct, lo: 0, hi: 15, sbHi: 50, step: 1, format: "%.0f"),
		DSlider(label: "Less fire and lava harm %", kp: \.fireCut, lo: 0, hi: 60, sbHi: 60, step: 1, format: "%.0f"),
		DSlider(label: "Less cold %", kp: \.coldCut, lo: 0, hi: 75, sbHi: 75, step: 1, format: "%.0f"),
		DSlider(label: "Less lightning and hail %", kp: \.stormCut, lo: 0, hi: 60, sbHi: 60, step: 1, format: "%.0f"),
		DSlider(label: "Healing a minute (armour)", kp: \.regen, lo: 0, hi: 12, sbHi: 60, step: 0.5, format: "%.1f"),
		DSlider(label: "Less suit energy %", kp: \.energyPct, lo: 0, hi: 50, sbHi: 50, step: 1, format: "%.0f"),
	]
	static let strikes: [DSlider<ModInfusion>] = [
		DSlider(label: "Sets alight (seconds)", kp: \.burn, lo: 0, hi: 8, sbHi: 8, step: 0.5, format: "%.1f"),
		DSlider(label: "Slows (seconds)", kp: \.slow, lo: 0, hi: 8, sbHi: 8, step: 0.5, format: "%.1f"),
		DSlider(label: "Poisons (seconds)", kp: \.poison, lo: 0, hi: 10, sbHi: 10, step: 0.5, format: "%.1f"),
		DSlider(label: "Spark chance", kp: \.sparkChance, lo: 0, hi: 0.4, sbHi: 1, step: 0.01, format: "%.2f"),
		DSlider(label: "Little blast (damage)", kp: \.blast, lo: 0, hi: 8, sbHi: 40, step: 0.5, format: "%.1f"),
		DSlider(label: "Health stolen %", kp: \.lifeSteal, lo: 0, hi: 15, sbHi: 50, step: 1, format: "%.0f"),
		DSlider(label: "Blow returned % (armour)", kp: \.thorns, lo: 0, hi: 40, sbHi: 40, step: 1, format: "%.0f"),
	]

	var body: some View {
		VStack(spacing: 10) {
			aboutSection
			iconSection
			goesOnSection
			ModSection(title: "NUMBERS", help: "Percentages of what the item already does, so a good item stays better than a poor one") {
				ModToggle(label: "Percentages multiply", help: "Off: they add to those of other infusions", isOn: b(\.multiply, false))
				sliders(InfusionEditorView.numbers)
			}
			ModSection(title: "WHEN IT STRIKES", help: "What happens to what a weapon or shot hits") {
				sliders(InfusionEditorView.strikes)
			}
			effectSection
			ModSection(title: "STACKING AND LOOKS") {
				IntSlider(label: "Times one item may hold it", value: b(\.stack, 1), range: 1...3)
				ModToggle(label: "Sparks of its colour when it works", isOn: b(\.particles, true))
			}
			recipeSection
			previewSection
		}
	}

	var aboutSection: some View {
		ModSection(title: "ABOUT") {
			ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Thunderstrike")
			ModTextField(label: "Description", text: b(\.desc, ""), placeholder: "Optional")
			Text("Rarity").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			ChoiceRow(options: InfusionEditorView.rarityNames, selected: b(\.rarity, 1), columns: 5)
			ModColorRow(label: "Its colour (sparks and marks on items)", color: b(\.color, 0x60E0FF))
		}
	}
	static let rarityNames: [String] = Rarity.allCases.map { $0.name }

	var iconSection: some View {
		ModSection(title: "COMPOUND ICON", help: "Leave it blank for a phial in its colour") {
			PixelEditorView(pixels: b(\.icon, ModPixels(w: 12, h: 12)), maxSide: 240, sizes: [12, 16], outlineDefault: true)
		}
	}

	var goesOnSection: some View {
		let f: ModInfusion = inf
		return ModSection(title: "GOES ON", help: "Kinds of equipment, or (if any are picked below) only certain items") {
			classChips(f)
			itemList(f)
		}
	}

	var effectSection: some View {
		let on: Bool = inf.trigger != .none
		return ModSection(title: "EFFECT ON YOU", help: "A timed effect for the player, given now and then") {
			ChoiceRow(options: InfusionEditorView.triggerNames, selected: triggerBind, columns: 3)
			if on {
				effectEditor
				StatSlider(label: "Rests between (seconds)", value: b(\.effectCooldown, 10), range: 2...300, step: 1, format: "%.0f")
			}
		}
	}
	static let triggerNames: [String] = ModInfuseTrigger.allCases.map { $0.name }

	var recipeSection: some View {
		let key: String = s.mod.key(inf.id)
		let recs: [ModRecipe] = s.mod.recipes.filter { $0.out == .custom(key) }
		return ModSection(title: "ITS COMPOUND'S RECIPE") {
			ForEach(recs) { r in self.recipeRow(r) }
			SmallButton(title: "+ MAKE A RECIPE FOR IT", color: ModUI.accent) { self.makeRecipe(key) }
		}
	}

	func recipeRow(_ r: ModRecipe) -> some View {
		let names: String = r.cost.map { $0.item.name }.joined(separator: ", ")
		let line: String = joinText("Recipe ", r.id, ": ", names)
		return HStack {
			Text(verbatim: line).font(.pixel(11, .semibold)).foregroundColor(Color.white).lineLimit(1)
			Spacer()
			SmallButton(title: "EDIT", color: ModUI.blue) { self.openRecipe(r.id) }
		}
	}

	func makeRecipe(_ key: String) {
		var r = ModRecipe()
		r.id = s.mod.freshID("r")
		r.out = .custom(key)
		r.count = 1
		r.cost = [ModCost(.mat(.waterVial), 1), ModCost(.mat(.crystalShard), 1)]
		r.station = Station.infuser.rawValue
		s.mod.recipes.append(r)
		s.touch()
		openRecipe(r.id)
	}

	var previewSection: some View {
		let f: ModInfusion = inf
		let rows: [(String, String, String)] = previewRows(f)
		return ModSection(title: "PREVIEW", help: "What it would do to a sample item of the first kind it goes on") {
			ForEach(0..<rows.count, id: \.self) { i in PreviewRow(name: rows[i].0, before: rows[i].1, after: rows[i].2) }
			Text(verbatim: f.blurb).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
		}
	}

	func sliders(_ list: [DSlider<ModInfusion>]) -> some View {
		let sb: Bool = s.mod.sandbox
		return VStack(alignment: .leading, spacing: 8) {
			ForEach(0..<list.count, id: \.self) { i in self.slider(list[i], sb) }
		}
	}

	func slider(_ d: DSlider<ModInfusion>, _ sb: Bool) -> StatSlider {
		let top: Double = sb ? d.sbHi : d.hi
		let r: ClosedRange<Double> = d.lo...top
		return StatSlider(label: d.label, value: b(d.kp, 0), range: r, step: d.step, format: d.format)
	}

	var triggerBind: Binding<Int> {
		let inner: Binding<ModInfuseTrigger> = b(\.trigger, .none)
		return Binding<Int>(get: { inner.wrappedValue.rawValue }, set: { inner.wrappedValue = ModInfuseTrigger(rawValue: $0) ?? .none })
	}

	var effectEditor: some View {
		let e: Binding<ModEffect> = b(\.effect, ModEffect(.speed, 20, 8))
		let timed: [ModEffectKind] = ModEffectKind.allCases.filter { $0.timed }
		let kindB: Binding<Int> = Binding<Int>(get: { timed.firstIndex(of: e.wrappedValue.kind) ?? 0 }, set: { v in
			var x: ModEffect = e.wrappedValue
			x.kind = timed[clampI(v, 0, timed.count - 1)]
			x.amount = x.kind.amountRange.clamp(x.amount, s.mod.sandbox)
			e.wrappedValue = x
		})
		let amount: Binding<Double> = Binding<Double>(get: { e.wrappedValue.amount }, set: { v in var x: ModEffect = e.wrappedValue; x.amount = v; e.wrappedValue = x })
		let secs: Binding<Double> = Binding<Double>(get: { e.wrappedValue.seconds }, set: { v in var x: ModEffect = e.wrappedValue; x.seconds = v; e.wrappedValue = x })
		let range: ModRange = e.wrappedValue.kind.amountRange
		return VStack(alignment: .leading, spacing: 6) {
			ChoiceRow(options: timed.map { $0.name }, selected: kindB, columns: 4)
			StatSlider(label: e.wrappedValue.kind.amountLabel, value: amount, range: range.lo...(s.mod.sandbox ? range.sandboxHi : range.hi), step: 0.5)
			StatSlider(label: "Seconds", value: secs, range: 1...120, step: 1, format: "%.0f")
		}
	}

	func classChips(_ f: ModInfusion) -> some View {
		let names: [String] = ["Melee weapons", "Bows, slings and guns", "Tools", "Armour and suit plating", "Suit cores and modules"]
		let cls: Binding<[Int]> = b(\.classes, [0])
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 150), spacing: 6)]
		return LazyVGrid(columns: cols, spacing: 6) {
			ForEach(0..<names.count, id: \.self) { i in
				let on: Bool = cls.wrappedValue.contains(i)
				SmallButton(title: names[i], color: on ? ModUI.accent : Color(ui: 0x555555)) {
					if on { cls.wrappedValue.removeAll { $0 == i } } else { cls.wrappedValue.append(i) }
				}
			}
		}
	}

	func itemList(_ f: ModInfusion) -> some View {
		let items: Binding<[Item]> = b(\.items, [])
		return VStack(alignment: .leading, spacing: 6) {
			Text(verbatim: f.items.isEmpty ? "Any item of the kinds picked" : "Only these items:").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ForEach(0..<f.items.count, id: \.self) { i in
				HStack {
					Art.shared.icon(f.items[i]).resizable().interpolation(.none).frame(width: 24, height: 24)
					Text(verbatim: f.items[i].name).font(.pixel(11)).foregroundColor(Color.white)
					Spacer()
					SmallButton(title: "✕", color: ModUI.red) { if i < items.wrappedValue.count { items.wrappedValue.remove(at: i) } }
				}
			}
			if pickingItem {
				GamePickerView(kind: .item, title: "ONLY ON THIS ITEM", pick: { _, it in
					if let x = it, !items.wrappedValue.contains(x) { items.wrappedValue.append(x) }
					pickingItem = false
				}, cancel: { pickingItem = false })
			} else if f.items.count < 12 {
				SmallButton(title: "+ ONLY ON A CERTAIN ITEM", color: ModUI.blue) { pickingItem = true }
			}
		}
	}

	/// Before-and-after numbers on a sample item of its first kind
	func previewRows(_ f: ModInfusion) -> [(String, String, String)] {
		var rows: [(String, String, String)] = []
		let first: Int = f.classes.first ?? 0
		func f1(_ v: Double) -> String { return String(format: "%.1f", v) }
		switch first {
		case 0, 1:
			let it: Item = first == 0 ? .sword(.iron) : .gun(.pistol)
			let p0: MeleeProfile = first == 0 ? it.melee : MeleeProfile(damage: GunType.pistol.damage, cooldown: GunType.pistol.cooldown, reach: 14, halfArc: 0)
			let p1: MeleeProfile = f.apply(p0)
			rows.append((joinText(it.name, " damage"), f1(p0.damage), f1(p1.damage)))
			rows.append(("Time between attacks", String(format: "%.2f s", p0.cooldown), String(format: "%.2f s", p1.cooldown)))
			if first == 0 {
				rows.append(("Reach", f1(p0.reach), f1(p1.reach)))
				rows.append(("Critical chance", joinText(String(Int(p0.critChance * 100)), "%"), joinText(String(Int(p1.critChance * 100)), "%")))
			}
		case 2:
			let s0: Double? = miningSeconds(.stone, .pickaxe, .iron)
			let s1: Double? = s0.map { $0 / max(0.01, 1.0 + f.miningPct / 100.0) }
			rows.append(("Iron pickaxe on stone", secondsText(s0), secondsText(s1)))
		default:
			let d0: Double = Tier.iron.defense * ArmorSlot.chest.weight
			rows.append(("Iron chestplate defence", f1(d0), f1(d0 + f.defense)))
			rows.append(("Run speed", "100%", joinText(String(Int((100 + f.moveSpeedPct).rounded())), "%")))
		}
		return rows
	}
}

extension InfusionPanel {
	/// The world's custom infusions (from its mods), in the crucible beside the game's own
	var customRows: some View {
		let list: [ModInfusionRT] = ModRuntime.shared.infusionDefs.values.sorted { $0.number < $1.number }
		return VStack(spacing: 4) {
			if !list.isEmpty {
				Text("FROM MODS").font(.pixel(11)).foregroundColor(Color(ui: 0xB8A8D8)).frame(maxWidth: .infinity, alignment: .leading)
			}
			ForEach(list, id: \.number) { r in customRow(r) }
		}
	}

	func customRow(_ r: ModInfusionRT) -> some View {
		let compound: Item = .custom(r.key)
		let owned: Int = game.inv.total(compound)
		let chosen: Bool = customChoice == r.number
		return Button(action: {
			customChoice = r.number
			choice = -1
			note = ""
		}) {
			HStack(spacing: 6) {
				SlotView(stack: Stack(item: compound, count: max(1, owned)), selected: chosen, size: 34, dim: owned == 0)
				VStack(alignment: .leading, spacing: 1) {
					Text(verbatim: r.def.name).font(.pixel(12)).foregroundColor(Color(ui: (Rarity(rawValue: r.def.rarity) ?? .uncommon).color))
					Text(verbatim: r.def.blurb).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.8)).lineLimit(2)
				}
				Spacer(minLength: 0)
				Text(verbatim: owned > 0 ? joinText("x", String(owned)) : "none").font(.pixel(10)).foregroundColor(Color.white.opacity(0.6))
			}
			.padding(4)
			.background(chosen ? Color(ui: 0x4A3A6A) : Color.black.opacity(0.2))
		}
		.buttonStyle(.plain)
	}

	func customPreview(_ s: Stack, _ r: ModInfusionRT) -> some View {
		let problem: String? = s.customProblem(r)
		let owned: Int = game.inv.total(.custom(r.key))
		let ok: Bool = problem == nil && (owned > 0 || game.isCreative)
		let p0: MeleeProfile = s.item.melee
		let p1: MeleeProfile = r.def.apply(p0)
		return VStack(alignment: .leading, spacing: 5) {
			Text(verbatim: joinText(s.item.name, " + ", r.def.name)).font(.pixel(12))
			Text(verbatim: r.def.blurb).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.8))
			if infuseClasses(s.item).contains(.melee) {
				Text(verbatim: joinText("Damage ", String(format: "%.1f", p0.damage), " → ", String(format: "%.1f", p1.damage))).font(.pixel(11)).foregroundColor(Color.white)
			}
			if let p = problem { Text(verbatim: p).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xFF9A7A)) }
			PixelButton(title: ok ? "CONFIRM INFUSION" : "CAN'T INFUSE", color: ok ? Color(ui: 0x6A4AA8) : Color(ui: 0x444444)) {
				if !ok { return }
				note = game.infuseCustom(slot: pick, r.number)
				customChoice = -1
			}
		}
		.padding(6)
		.background(Color.black.opacity(0.25))
	}
}

// MARK: - Mod Creator+: boss phases and summoning (screens)

/// The PHASES page of a creature: the stages of its fight, shown along its health bar
struct BossPhasesPage: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var open: Int = 0

	static let gameHelpers: [MobKind] = [.zombie, .skeleton, .slime, .bat, .scorpion, .wraith, .imp, .emberSlime, .cinderBat, .crawler, .archer, .pirate]

	var mob: ModMob { return s.mod.mobs.first { $0.id == id } ?? ModMob() }
	var phases: Binding<[ModPhase]> { return s.bind(\ModPack.mobs, id, \ModMob.phases, []) }
	var sb: Bool { return s.mod.sandbox }

	func pb<T>(_ i: Int, _ kp: WritableKeyPath<ModPhase, T>, _ d: T) -> Binding<T> {
		let base: Binding<[ModPhase]> = phases
		return Binding<T>(get: { i < base.wrappedValue.count ? base.wrappedValue[i][keyPath: kp] : d }, set: { v in
			var list: [ModPhase] = base.wrappedValue
			if i < list.count {
				list[i][keyPath: kp] = v
				base.wrappedValue = list
			}
		})
	}

	var body: some View {
		VStack(spacing: 10) {
			Text("A fight in stages. Each phase begins when its moment comes and changes the creature for the rest of the fight; phases follow one another in order. They work for any creature, and bosses show the phase on their health bar.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			timeline
			ForEach(0..<mob.phases.count, id: \.self) { i in phaseCard(i) }
			if mob.phases.count < ModLimits.maxPhases {
				PixelButton(title: "+ ADD PHASE", color: ModUI.accent) { add() }
			}
		}
	}

	/// The fight along the health bar: where each health phase begins, then the others in order
	var timeline: some View {
		let segs: [(Double, UInt32, String)] = segments
		let others: [String] = laterPhases
		return VStack(alignment: .leading, spacing: 4) {
			Text("THE FIGHT, FULL HEALTH TO NONE").font(.pixel(12, .bold)).foregroundColor(ModUI.gold)
			HStack(spacing: 2) {
				ForEach(0..<segs.count, id: \.self) { k in BossPhasesPage.segmentView(segs[k]) }
			}
			ForEach(0..<others.count, id: \.self) { k in
				Text(verbatim: others[k]).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	static func segmentView(_ seg: (Double, UInt32, String)) -> some View {
		let w: CGFloat = CGFloat(max(10.0, seg.0 * 420.0))
		let col: Color = Color(ui: seg.1)
		return VStack(spacing: 2) {
			Rectangle().fill(col).frame(width: w, height: 16)
			Text(verbatim: seg.2).font(.pixel(9, .semibold)).foregroundColor(Color.white).lineLimit(1).frame(width: w)
		}
	}

	/// Stretches of the health bar: (share, colour, the phase's name)
	var segments: [(Double, UInt32, String)] {
		var out: [(Double, UInt32, String)] = []
		var from: Double = 1.0
		var col: UInt32 = 0x5AA85A
		var name: String = "Start"
		for p in mob.phases where p.when == .health && p.value < from {
			out.append((from - p.value, col, name))
			from = p.value
			col = p.tintAmt > 0.05 ? p.tint : 0xA05050
			name = p.name
		}
		out.append((from, col, name))
		return out
	}

	var laterPhases: [String] {
		var out: [String] = []
		for (i, p) in mob.phases.enumerated() where p.when != .health {
			out.append(joinText("Phase ", String(i + 1), " \u{201C}", p.name, "\u{201D} begins ", p.whenText, "."))
		}
		return out
	}

	func phaseCard(_ i: Int) -> some View {
		let p: ModPhase = i < mob.phases.count ? mob.phases[i] : ModPhase()
		let isOpen: Bool = open == i
		return VStack(alignment: .leading, spacing: 8) {
			cardHeader(i, p)
			Text(verbatim: summary(p)).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			if isOpen { editor(i, p) }
		}
		.padding(10)
		.background(PixelBox(color: ModUI.card))
	}

	func cardHeader(_ i: Int, _ p: ModPhase) -> some View {
		let title: String = joinText(String(i + 1), ". ", p.name, " \u{2014} ", p.whenText)
		let toggle: String = open == i ? "CLOSE" : "EDIT"
		let canUp: Bool = i > 0
		let canDown: Bool = i < mob.phases.count - 1
		return HStack(spacing: 6) {
			Rectangle().fill(Color(hex: p.tint)).frame(width: 14, height: 14)
			Text(verbatim: title).font(.pixel(13, .bold)).foregroundColor(Color.white)
			Spacer(minLength: 0)
			SmallButton(title: toggle, color: ModUI.blue) { self.toggleOpen(i) }
			if canUp { SmallButton(title: "UP") { self.move(i, -1) } }
			if canDown { SmallButton(title: "DOWN") { self.move(i, 1) } }
			SmallButton(title: "DELETE", color: ModUI.red) { self.remove(i) }
		}
	}

	func toggleOpen(_ i: Int) { open = open == i ? -1 : i }

	func summary(_ p: ModPhase) -> String {
		var parts: [String] = []
		parts.append(String(format: "speed x%.2f", p.speedMul))
		parts.append(String(format: "damage x%.2f", p.damageMul))
		if abs(p.cooldownMul - 1) > 0.01 { parts.append(String(format: "attacks rest x%.2f", p.cooldownMul)) }
		if p.defense > 0.01 { parts.append(joinText("shrugs off ", String(Int((p.defense * 100).rounded())), "%")) }
		if p.heal > 0.01 { parts.append(joinText("heals ", String(Int((p.heal * 100).rounded())), "%")) }
		if p.helpers > 0 && !p.helper.isEmpty { parts.append(joinText("calls ", String(p.helpers), " helpers")) }
		if !p.attacks.isEmpty { parts.append(joinText("uses ", String(p.attacks.count), " of its attacks")) }
		return parts.joined(separator: " \u{00B7} ")
	}

	func editor(_ i: Int, _ p: ModPhase) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			ModTextField(label: "Name", text: pb(i, \.name, ""), placeholder: "Enraged")
			whenSection(i, p)
			changeSection(i)
			if !mob.attacks.isEmpty { attacksSection(i) }
			lookSection(i, p)
			helpersSection(i, p)
			ModTextField(label: "Message", text: pb(i, \.message, ""), placeholder: "The ground splits open!")
		}
	}

	static let whenNames: [String] = ModPhaseWhen.allCases.map { $0.name }

	func whenSection(_ i: Int, _ p: ModPhase) -> some View {
		let health: Bool = p.when == .health
		let time: Bool = p.when == .time
		return ModSection(title: "WHEN IT BEGINS", help: p.when.help) {
			ChoiceRow(options: BossPhasesPage.whenNames, selected: whenBind(i), columns: 3)
			if health {
				StatSlider(label: "Health", value: percent(pb(i, \.value, 0.5)), range: 5.0...95.0, step: 1, format: "%.0f", unit: "%")
			}
			if time {
				StatSlider(label: "Seconds of fighting", value: pb(i, \.value, 30), range: 3.0...600.0, step: 1, format: "%.0f", unit: " s")
			}
		}
	}

	func changeSection(_ i: Int) -> some View {
		let sb: Bool = self.sb
		return ModSection(title: "HOW IT CHANGES", help: "Multipliers of its own numbers, for the rest of the fight.") {
			StatSlider(label: "Speed", value: pb(i, \.speedMul, 1), range: sbRange(0.5, 2, 3, sb), step: 0.05, format: "x%.2f")
			StatSlider(label: "Damage", value: pb(i, \.damageMul, 1), range: sbRange(0.5, 3, 6, sb), step: 0.05, format: "x%.2f")
			StatSlider(label: "Rest between attacks", value: pb(i, \.cooldownMul, 1), range: 0.3...2.0, step: 0.05, format: "x%.2f")
			StatSlider(label: "Hits shrugged off", value: percent(pb(i, \.defense, 0)), range: sbRange(0, 60, 90, sb), step: 1, format: "%.0f", unit: "%")
			StatSlider(label: "Heals as it begins", value: percent(pb(i, \.heal, 0)), range: 0.0...50.0, step: 1, format: "%.0f", unit: "%")
			StatSlider(label: "Can't be hurt while changing", value: pb(i, \.shield, 1), range: 0.0...5.0, step: 0.25, format: "%.2f", unit: " s")
		}
	}

	func attacksSection(_ i: Int) -> some View {
		let names: [String] = mob.attacks.enumerated().map { (j: Int, a: ModAttack) -> String in joinText("Attack ", String(j + 1), ": ", a.kind.name) }
		return ModSection(title: "ATTACKS IN THIS PHASE", help: "All on: it uses every attack it has.") {
			ForEach(0..<names.count, id: \.self) { j in ModToggle(label: names[j], isOn: self.attackBind(i, j)) }
		}
	}

	func lookSection(_ i: Int, _ p: ModPhase) -> some View {
		let img: Image = tinted(p)
		return ModSection(title: "LOOK") {
			HStack(spacing: 12) {
				img.resizable().interpolation(.none).frame(width: 72, height: 72).background(Color(ui: 0x5A7A9A).opacity(0.6))
				VStack(alignment: .leading, spacing: 6) {
					StatSlider(label: "Colour strength", value: pb(i, \.tintAmt, 0.25), range: 0.0...1.0, step: 0.05, format: "%.2f")
					ModToggle(label: "Roars as it begins", isOn: pb(i, \.roar, true))
				}
			}
			ModColorRow(label: "Colour", color: pb(i, \.tint, 0xFF4030))
		}
	}

	func helpersSection(_ i: Int, _ p: ModPhase) -> some View {
		let names: [String] = helperChoices.0
		let has: Bool = !p.helper.isEmpty
		let most: ClosedRange<Int> = 0...(sb ? 10 : 6)
		return ModSection(title: "HELPERS", help: "Creatures it calls to its side as this phase begins.") {
			ChoiceRow(options: names, selected: helperBind(i), columns: 4)
			if has { IntSlider(label: "How many", value: pb(i, \.helpers, 0), range: most) }
		}
	}

	func percent(_ b: Binding<Double>) -> Binding<Double> {
		return Binding<Double>(get: { b.wrappedValue * 100.0 }, set: { b.wrappedValue = $0 / 100.0 })
	}

	func whenBind(_ i: Int) -> Binding<Int> {
		let base: Binding<ModPhaseWhen> = pb(i, \.when, .health)
		let val: Binding<Double> = pb(i, \.value, 0.5)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { n in
			let w: ModPhaseWhen = ModPhaseWhen(rawValue: n) ?? .health
			if w != base.wrappedValue {
				base.wrappedValue = w
				val.wrappedValue = w == .time ? 30 : 0.5
			}
		})
	}

	/// One attack switched on or off for a phase (all on is stored as "every attack")
	func attackBind(_ i: Int, _ j: Int) -> Binding<Bool> {
		let base: Binding<[Int]> = pb(i, \.attacks, [])
		let n: Int = mob.attacks.count
		return Binding<Bool>(get: { base.wrappedValue.isEmpty || base.wrappedValue.contains(j) }, set: { on in
			var l: [Int] = base.wrappedValue.isEmpty ? Array(0..<n) : base.wrappedValue
			if on {
				if !l.contains(j) { l.append(j) }
			} else {
				// at least one attack stays on
				if l.count <= 1 { return }
				l.removeAll { $0 == j }
			}
			l.sort()
			base.wrappedValue = l.count >= n ? [] : l
		})
	}

	var helperChoices: ([String], [String]) {
		var names: [String] = ["Nobody"]
		var keys: [String] = [""]
		for o in s.mod.mobs where o.id != id {
			names.append(o.name)
			keys.append(s.mod.key(o.id))
		}
		for k in BossPhasesPage.gameHelpers {
			names.append(mobDef(k).name)
			keys.append(mobDef(k).name)
		}
		return (names, keys)
	}

	func helperBind(_ i: Int) -> Binding<Int> {
		let base: Binding<String> = pb(i, \.helper, "")
		let count: Binding<Int> = pb(i, \.helpers, 0)
		let keys: [String] = helperChoices.1
		return Binding<Int>(get: { keys.firstIndex(of: base.wrappedValue) ?? 0 }, set: { n in
			base.wrappedValue = keys[clampI(n, 0, keys.count - 1)]
			if base.wrappedValue.isEmpty { count.wrappedValue = 0 } else if count.wrappedValue == 0 { count.wrappedValue = 2 }
		})
	}

	/// The creature as it looks in this phase
	func tinted(_ p: ModPhase) -> Image {
		let fr: ([PixelBuf], CreatureAnim) = modMobFrames(mob)
		guard let f = fr.0.first else { return pixImage(PixelBuf(w: 1, h: 1)) }
		return pixImage(recolorBuf(f, hue: 0, sat: 1, bright: 1, tint: p.tint, amt: p.tintAmt))
	}

	func add() {
		var list: [ModPhase] = mob.phases
		var p = ModPhase()
		let health: [Double] = list.filter { $0.when == .health }.map { $0.value }
		let lowest: Double = health.min() ?? 1.0
		let next: Double = (lowest - 0.25).rounded(toPlaces: 2)
		p.value = max(0.1, next)
		p.name = list.isEmpty ? "Enraged" : joinText("Phase ", String(list.count + 1))
		list.append(p)
		phases.wrappedValue = list
		open = list.count - 1
	}

	func move(_ i: Int, _ d: Int) {
		var list: [ModPhase] = mob.phases
		let j: Int = i + d
		if i < 0 || j < 0 || i >= list.count || j >= list.count { return }
		list.swapAt(i, j)
		phases.wrappedValue = list
		open = j
	}

	func remove(_ i: Int) {
		var list: [ModPhase] = mob.phases
		if i < 0 || i >= list.count { return }
		list.remove(at: i)
		phases.wrappedValue = list
		open = -1
	}
}

extension Double {
	func rounded(toPlaces n: Int) -> Double {
		let f: Double = pow(10.0, Double(n))
		return (self * f).rounded() / f
	}
}

/// A summoning shape as a grid of big cells to paint
struct PatternGrid: View {
	@Binding var pattern: ModPattern
	let brush: String
	let catalog: ModCatalog

	var body: some View {
		VStack(spacing: 2) {
			ForEach(0..<pattern.h, id: \.self) { y in
				HStack(spacing: 2) {
					ForEach(0..<pattern.w, id: \.self) { x in
						Button(action: {
							var p: ModPattern = pattern
							p.set(x, y, p.cell(x, y) == brush ? "" : brush)
							pattern = p
						}) {
							PatternGrid.cellImage(pattern.cell(x, y), catalog).resizable().interpolation(.none)
								.frame(width: 46, height: 46)
								.background(Color.black.opacity(0.35))
						}
						.buttonStyle(.plain)
					}
				}
			}
		}
		.padding(6)
		.background(Color(ui: 0x6A8AAA).opacity(0.5))
	}

	/// The picture of a cell: a block, a cross for "empty", or a faint dot for "anything"
	static func cellImage(_ k: String, _ cat: ModCatalog) -> Image {
		if k.isEmpty {
			var b = PixelBuf(w: 8, h: 8)
			b.set(3, 3, 0xFF707070)
			b.set(4, 4, 0xFF707070)
			b.set(3, 4, 0xFF707070)
			b.set(4, 3, 0xFF707070)
			return pixImage(b)
		}
		if k == "air" {
			var b = PixelBuf(w: 8, h: 8)
			for i in 1..<7 {
				b.set(i, i, 0xFFE04040)
				b.set(7 - i, i, 0xFFE04040)
			}
			return pixImage(b)
		}
		if k.hasPrefix("tile:"), let n = Int(k.dropFirst(5)), let t = Tile(rawValue: UInt8(clampI(n, 0, 255))) { return pixImage(tileBuf(t)) }
		return ModPreview.icon(.custom(k), cat)
	}
}

// MARK: - Mod Creator+: summoning rules and custom dimensions (screens)

/// A chip that is on or off (tap to change it)
struct ToggleChip: View {
	let title: String
	let on: Bool
	var action: () -> Void
	var body: some View {
		let bg: Color = on ? ModUI.accent : Color.black.opacity(0.4)
		return Button(action: action) {
			Text(verbatim: title).font(.pixel(11, .bold)).foregroundColor(Color.white)
				.frame(maxWidth: .infinity, minHeight: 40)
				.background(bg)
		}
		.buttonStyle(.plain)
	}
}

/// One way to summon (or a dimension's way in): what the player does, the item, the shape, and when
/// and where it works. Used by the SUMMON page and the dimension editor.
struct SummonRuleEditor: View {
	@ObservedObject var s: ModSession
	@Binding var rule: ModSummon
	var forDimension: Bool = false
	@State var pickingItem: Bool = false
	@State var pickingBlock: Bool = false
	/// what a tap on the shape paints: "" anything, "air" empty, or a block key
	@State var brush: String = "air"
	@State var recent: [String] = []

	func rb<T>(_ kp: WritableKeyPath<ModSummon, T>) -> Binding<T> {
		return Binding<T>(get: { rule[keyPath: kp] }, set: { rule[keyPath: kp] = $0 })
	}

	var body: some View {
		ZStack {
			VStack(alignment: .leading, spacing: 8) {
				ModToggle(label: forDimension ? "Players can get in this way" : "Works in play", isOn: rb(\.enabled))
				howSection
				if rule.usesItem { itemSection }
				if rule.usesPattern { shapeSection }
				whereSection
				if !forDimension { entranceSection }
			}
		}
		.modCover(s, pickingItem ? 1 : nil) { self.itemPicker }
		.modCover(s, pickingBlock ? 2 : nil) { self.blockPicker }
	}

	static let howNames: [String] = ModSummonHow.allCases.map { $0.name }

	var howSection: some View {
		ModSection(title: "WHAT THE PLAYER DOES", help: rule.how.help) {
			ChoiceRows(options: SummonRuleEditor.howNames, selected: howBind, columns: 3)
		}
	}

	var itemSection: some View {
		let title: String = forDimension ? "THE KEY ITEM" : "THE ITEM"
		let help: String = forDimension ? "Using it again inside the dimension brings the player back." : ""
		let used: String = forDimension ? "Used up on the way in" : "Used up when the creature comes"
		return ModSection(title: title, help: help) {
			itemRow
			ModToggle(label: used, isOn: rb(\.consume))
		}
	}

	var itemRow: some View {
		HStack(spacing: 10) {
			if let it = rule.item {
				ModPreview.icon(it, s.catalog).resizable().interpolation(.none).frame(width: 36, height: 36)
			}
			Text(verbatim: itemName).font(.pixel(13, .bold)).foregroundColor(Color.white)
			Spacer(minLength: 0)
			SmallButton(title: "CHOOSE", color: ModUI.blue) { self.pickingItem = true }
		}
	}

	var shapeSection: some View {
		let title: String = forDimension ? "THE GATEWAY SHAPE" : "THE SHAPE"
		return ModSection(title: title, help: "Tap a cell to paint it. ANY: the cell can hold anything. EMPTY: it must be clear. It is built facing the way it is drawn.") {
			palette
			PatternGrid(pattern: rb(\.pattern), brush: brush, catalog: s.catalog)
			sizeRow
			ModToggle(label: "The shape's blocks are used up", isOn: rb(\.clearPattern))
		}
	}

	var sizeRow: some View {
		let side: ClosedRange<Int> = 1...ModPattern.maxSide
		return HStack(spacing: 10) {
			IntSlider(label: "Width", value: sizeBind(true), range: side)
			IntSlider(label: "Height", value: sizeBind(false), range: side)
		}
	}

	var whereSection: some View {
		ModSection(title: "WHEN AND WHERE", help: "Weather conditions are skipped for players who switch the weather off.") {
			ChoiceRows(options: ModSummonText.times, selected: rb(\.time), columns: 3)
			ChoiceRows(options: ModSummonText.weathers, selected: rb(\.weather), columns: 5)
			ChoiceRows(options: ModSummonText.places, selected: rb(\.place), columns: 3)
			ModBiomePicker(biomes: rb(\.biomes))
			Text("Dimensions (none chosen: any)").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			chips(SummonRuleEditor.gameDims, rb(\.dims))
			if !s.mod.dims.isEmpty { keyChips(modDims, rb(\.dimKeys)) }
		}
	}

	static let gameDims: [(Int, String)] = [(0, "Overworld"), (1, "Umbral Realm")]

	var modDims: [(String, String)] {
		var out: [(String, String)] = []
		for d in s.mod.dims { out.append((s.mod.key(d.id), d.name)) }
		return out
	}

	var entranceSection: some View {
		ModSection(title: "ITS ENTRANCE") {
			ChoiceRows(options: ModSummonText.appears, selected: rb(\.appear), columns: 2)
			ModTextField(label: "Message", text: rb(\.message), placeholder: "The Frost King answers your call!")
		}
	}

	var itemPicker: some View {
		let title: String = forDimension ? "THE KEY ITEM" : "THE SUMMONING ITEM"
		return ItemPickerView(catalog: s.catalog, title: title, pick: { (it: Item) in
			self.rule.item = it
			self.pickingItem = false
		}, cancel: { self.pickingItem = false })
	}

	var blockPicker: some View {
		ItemPickerView(catalog: s.catalog, title: "A BLOCK FOR THE SHAPE", blocksOnly: true, pick: { (it: Item) in
			self.useBlock(it)
		}, cancel: { self.pickingBlock = false })
	}

	func useBlock(_ it: Item) {
		let k: String = SummonRuleEditor.key(it)
		if !k.isEmpty {
			brush = k
			recent.removeAll { $0 == k }
			recent.insert(k, at: 0)
			if recent.count > 8 { recent = Array(recent.prefix(8)) }
		}
		pickingBlock = false
	}

	static func key(_ it: Item) -> String {
		switch it {
		case .block(let t): return t.isMod || t == .air ? "" : ModGround.key(t)
		case .custom(let k): return k
		default: return ""
		}
	}

	var itemName: String {
		guard let i = rule.item else { return "None chosen" }
		return ModPreview.name(i, s.catalog)
	}

	var palette: some View {
		let n: Int = recent.count + 3
		return PlainGrid(count: n, per: 6) { (i: Int) in self.paletteCell(i) }
	}

	/// ANY, EMPTY, the blocks used lately, then + BLOCK
	@ViewBuilder
	func paletteCell(_ i: Int) -> some View {
		if i == 0 {
			brushButton("", "ANY")
		} else if i == 1 {
			brushButton("air", "EMPTY")
		} else if i - 2 < recent.count {
			brushButton(recent[i - 2], ModGround.name(recent[i - 2], s.mod))
		} else {
			Button(action: { self.pickingBlock = true }) {
				Text("+ BLOCK").font(.pixel(11, .bold)).foregroundColor(Color.white)
					.frame(maxWidth: .infinity, minHeight: 52)
					.background(ModUI.blue)
			}
			.buttonStyle(.plain)
		}
	}

	func brushButton(_ k: String, _ label: String) -> some View {
		let on: Bool = brush == k
		let bg: Color = on ? ModUI.accent : Color.black.opacity(0.4)
		let img: Image = PatternGrid.cellImage(k, s.catalog)
		return Button(action: { self.brush = k }) {
			VStack(spacing: 2) {
				img.resizable().interpolation(.none).frame(width: 28, height: 28)
				Text(verbatim: label).font(.pixel(8, .semibold)).foregroundColor(Color.white).lineLimit(1)
			}
			.frame(maxWidth: .infinity, minHeight: 52)
			.background(bg)
		}
		.buttonStyle(.plain)
	}

	func chips(_ opts: [(Int, String)], _ b: Binding<[Int]>) -> some View {
		let chosen: [Int] = b.wrappedValue
		return PlainGrid(count: opts.count, per: 4) { (k: Int) in
			ToggleChip(title: opts[k].1, on: chosen.contains(opts[k].0)) { SummonRuleEditor.flip(b, opts[k].0) }
		}
	}

	func keyChips(_ opts: [(String, String)], _ b: Binding<[String]>) -> some View {
		let chosen: [String] = b.wrappedValue
		return PlainGrid(count: opts.count, per: 4) { (k: Int) in
			ToggleChip(title: opts[k].1, on: chosen.contains(opts[k].0)) { SummonRuleEditor.flipKey(b, opts[k].0) }
		}
	}

	static func flip(_ b: Binding<[Int]>, _ v: Int) {
		var l: [Int] = b.wrappedValue
		if let j = l.firstIndex(of: v) { l.remove(at: j) } else { l.append(v) }
		b.wrappedValue = l.sorted()
	}

	static func flipKey(_ b: Binding<[String]>, _ v: String) {
		var l: [String] = b.wrappedValue
		if let j = l.firstIndex(of: v) { l.remove(at: j) } else { l.append(v) }
		b.wrappedValue = l
	}

	var howBind: Binding<Int> {
		return Binding<Int>(get: { rule.how.rawValue }, set: { rule.how = ModSummonHow(rawValue: $0) ?? .useItem })
	}

	func sizeBind(_ across: Bool) -> Binding<Int> {
		return Binding<Int>(get: { across ? rule.pattern.w : rule.pattern.h }, set: { n in
			let p: ModPattern = rule.pattern
			rule.pattern = across ? p.resized(n, p.h) : p.resized(p.w, n)
		})
	}
}

/// The SUMMON page of a creature: the ways a player can call it into the world
struct SummonPage: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var open: Int = 0

	var mob: ModMob { return s.mod.mobs.first { $0.id == id } ?? ModMob() }
	var summons: Binding<[ModSummon]> { return s.bind(\ModPack.mobs, id, \ModMob.summons, []) }

	func rule(_ i: Int) -> Binding<ModSummon> {
		let base: Binding<[ModSummon]> = summons
		return Binding<ModSummon>(get: { i < base.wrappedValue.count ? base.wrappedValue[i] : ModSummon() }, set: { v in
			var list: [ModSummon] = base.wrappedValue
			if i < list.count {
				list[i] = v
				base.wrappedValue = list
			}
		})
	}

	var body: some View {
		VStack(spacing: 10) {
			Text("Ways for a player to call this creature into the world in normal play: with an item, a shape of blocks, or both, where and when you say. Every condition you set must hold at once.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ForEach(0..<mob.summons.count, id: \.self) { i in card(i) }
			if mob.summons.count < ModLimits.maxSummons {
				PixelButton(title: "+ ADD A WAY TO SUMMON", color: ModUI.accent) { add() }
			}
		}
	}

	func itemName(_ it: Item?) -> String {
		guard let i = it else { return "an item (none chosen)" }
		return ModPreview.name(i, s.catalog)
	}

	func card(_ i: Int) -> some View {
		let sm: ModSummon = i < mob.summons.count ? mob.summons[i] : ModSummon()
		return VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 6) {
				Text(verbatim: joinText(String(i + 1), ". ", sm.how.name)).font(.pixel(13, .bold)).foregroundColor(sm.enabled ? Color.white : ModUI.dim)
				Spacer(minLength: 0)
				SmallButton(title: open == i ? "CLOSE" : "EDIT", color: ModUI.blue) { open = open == i ? -1 : i }
				SmallButton(title: "DELETE", color: ModUI.red) { remove(i) }
			}
			Text(verbatim: joinText(ModSummonText.describe(sm, itemName(sm.item)), sm.enabled ? "." : " (switched off).")).font(.pixel(10, .semibold)).foregroundColor(ModUI.gold)
			if open == i { SummonRuleEditor(s: s, rule: rule(i)) }
		}
		.padding(10)
		.background(PixelBox(color: ModUI.card))
	}

	func add() {
		var list: [ModSummon] = mob.summons
		var sm = ModSummon()
		sm.time = 2
		sm.message = joinText(mob.name, " answers the call!")
		list.append(sm)
		summons.wrappedValue = list
		open = list.count - 1
	}

	func remove(_ i: Int) {
		var list: [ModSummon] = mob.summons
		if i < 0 || i >= list.count { return }
		list.remove(at: i)
		summons.wrappedValue = list
		open = -1
	}
}

/// The DIMENSIONS tab: the mod's dimensions
struct DimensionListView: View {
	@ObservedObject var s: ModSession
	var open: (String) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Whole new places to travel to: their own sky, light, land, regions, weather and creatures, and a way in that you design (a key item, a gateway shape, or both). A world holds up to three custom dimensions.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			if s.mod.dims.count < 3 {
				PixelButton(title: "+ NEW DIMENSION", color: ModUI.accent) { add() }
			}
			ForEach(s.mod.dims) { d in
				Button(action: { open(d.id) }) {
					HStack(spacing: 10) {
						SkySwatch(top: d.skyTop, bottom: d.skyBottom).frame(width: 44, height: 44)
						VStack(alignment: .leading, spacing: 3) {
							Text(verbatim: d.name).font(.pixel(14)).foregroundColor(Color.white)
							Text(verbatim: summary(d)).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
						}
						Spacer(minLength: 0)
						if s.mod.off.contains(d.id) { Text("OFF").font(.pixel(11, .bold)).foregroundColor(ModUI.red) }
					}
					.padding(8)
					.frame(maxWidth: .infinity, alignment: .leading)
					.background(PixelBox(color: ModUI.card))
				}
				.buttonStyle(.plain)
			}
		}
	}

	func summary(_ d: ModDimension) -> String {
		var parts: [String] = []
		parts.append(d.ceiling ? "a cavern world" : "open sky")
		parts.append(joinText(String(d.zones.count), d.zones.count == 1 ? " region" : " regions"))
		if d.sea > 0 { parts.append(d.liquid == 1 ? "lava seas" : "seas") }
		if d.islands > 0.05 { parts.append("floating islands") }
		parts.append(joinText(String(d.spawns.count), d.spawns.count == 1 ? " creature" : " creatures"))
		parts.append(d.entry.enabled ? d.entry.how.name.lowercased() : "no way in yet")
		return parts.joined(separator: " \u{00B7} ")
	}

	func add() {
		var d = ModDimension()
		d.id = s.mod.freshID("d")
		d.name = joinText("Dimension ", String(s.mod.dims.count + 1))
		s.mod.dims.append(d)
		s.touch()
		open(d.id)
	}
}

/// Editing one dimension: its sky and light, its land, its regions, its creatures, the way in and out,
/// and a preview made by the game's own generator
/// A mod's own sun or moon: switched on, its picture (or the round one in its colour), how big it is,
/// its glow, rays, turning and pulsing, how it moves across the sky and how much light it gives. Used by
/// the dimension editor and, for the Overworld, by the GAME CONTENT tab.
struct SkyBodyEditor: View {
	@Binding var sky: ModSkyBody?
	let moon: Bool
	/// the sky's colour behind it in the preview
	var skyTop: UInt32 = 0x3E86D8
	var skyBottom: UInt32 = 0xB4DCFF
	@State var colorPick: Int = 0

	static let colorNames: [String] = ["Its colour", "Its glow"]
	static let pathNames: [String] = ["Rises and sets", "Stays in one place"]
	static let numbers: [DSlider<ModSkyBody>] = [
		DSlider(label: "Size (times the game's)", kp: \.size, lo: 0.3, hi: 3, sbHi: 3, step: 0.05, format: "%.2f"),
		DSlider(label: "Glow", kp: \.glow, lo: 0, hi: 1, sbHi: 1, step: 0.05, format: "%.2f"),
		DSlider(label: "Pulsing glow", kp: \.pulse, lo: 0, hi: 1, sbHi: 1, step: 0.05, format: "%.2f"),
		DSlider(label: "Turning (degrees a second)", kp: \.spin, lo: -180, hi: 180, sbHi: 180, step: 1, format: "%.0f"),
		DSlider(label: "Light it gives (1 = the game's)", kp: \.bright, lo: 0, hi: 2, sbHi: 2, step: 0.05, format: "%.2f")
	]
	static let pathNumbers: [DSlider<ModSkyBody>] = [
		DSlider(label: "How high it climbs", kp: \.arc, lo: 0.2, hi: 1.2, sbHi: 1.2, step: 0.05, format: "%.2f")
	]
	static let placeNumbers: [DSlider<ModSkyBody>] = [
		DSlider(label: "Across (left ... right)", kp: \.posX, lo: 0, hi: 1, sbHi: 1, step: 0.01, format: "%.2f"),
		DSlider(label: "Down (top ... horizon)", kp: \.posY, lo: 0, hi: 1, sbHi: 1, step: 0.01, format: "%.2f")
	]

	var fresh: ModSkyBody { return moon ? ModSkyBody.moon() : ModSkyBody() }

	func f<T>(_ kp: WritableKeyPath<ModSkyBody, T>) -> Binding<T> {
		let base: Binding<ModSkyBody?> = $sky
		let start: ModSkyBody = fresh
		return Binding<T>(get: { (base.wrappedValue ?? start)[keyPath: kp] }, set: { v in
			var b: ModSkyBody = base.wrappedValue ?? start
			b[keyPath: kp] = v
			base.wrappedValue = b
		})
	}

	var onBind: Binding<Bool> {
		let base: Binding<ModSkyBody?> = $sky
		let start: ModSkyBody = fresh
		return Binding<Bool>(get: { base.wrappedValue != nil }, set: { on in base.wrappedValue = on ? start : nil })
	}

	var body: some View {
		let own: Bool = sky != nil
		let word: String = moon ? "moon" : "sun"
		return VStack(alignment: .leading, spacing: 8) {
			ModToggle(label: joinText("Its own ", word), help: joinText("Off: the game's ", word, " as it always was"), isOn: onBind)
			if own { fields }
		}
	}

	var fields: some View {
		let b: ModSkyBody = sky ?? fresh
		let pick: Int = clampI(colorPick, 0, 1)
		let fixed: Bool = b.path == 1
		let pictured: Bool = !b.art.isBlank
		return VStack(alignment: .leading, spacing: 8) {
			SkyBodyPreview(b: b, moon: moon, top: skyTop, bottom: skyBottom).frame(height: 130)
			Text("Its picture (leave it blank for a round one in its colour)").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			PixelEditorView(pixels: f(\.art), maxSide: 240, sizes: [16, 24, 32], outlineDefault: false)
			if pictured { SmallButton(title: "BACK TO A ROUND ONE", color: ModUI.red) { self.f(\.art).wrappedValue = ModPixels(w: 16, h: 16) } }
			ChoiceRows(options: SkyBodyEditor.colorNames, selected: $colorPick, columns: 2)
			ModColorRow(label: SkyBodyEditor.colorNames[pick], color: pick == 0 ? f(\.color) : f(\.glowColor))
			ModToggle(label: "Rays", help: "Short rays all round it, in its glow's colour", isOn: f(\.rays))
			sliderRows(SkyBodyEditor.numbers)
			ChoiceRows(options: SkyBodyEditor.pathNames, selected: f(\.path), columns: 2)
			if fixed {
				Text("It hangs there day and night.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				sliderRows(SkyBodyEditor.placeNumbers)
			} else {
				sliderRows(SkyBodyEditor.pathNumbers)
			}
		}
	}

	func sliderRows(_ list: [DSlider<ModSkyBody>]) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			ForEach(0..<list.count, id: \.self) { (i: Int) in self.slider(list[i]) }
		}
	}

	func slider(_ d: DSlider<ModSkyBody>) -> StatSlider {
		let r: ClosedRange<Double> = d.lo...d.hi
		return StatSlider(label: d.label, value: f(d.kp), range: r, step: d.step, format: d.format)
	}
}

/// A strip of sky with a sun or moon in it, as the game draws it (at the top of its path, or where it stays)
struct SkyBodyPreview: View {
	let b: ModSkyBody
	let moon: Bool
	let top: UInt32
	let bottom: UInt32

	var body: some View {
		let body: ModSkyBody = b
		let isMoon: Bool = moon
		let t0: UInt32 = top
		let b0: UInt32 = bottom
		return Canvas { ctx, size in
			let w: Double = Double(size.width)
			let h: Double = Double(size.height)
			let full: CGRect = CGRect(x: 0, y: 0, width: w, height: h)
			vGradient(&ctx, full, [rgbColor(t0), rgbColor(b0)], 0, h)
			// noon for a sun, midnight for a moon: the top of its path
			WorldRenderer.drawSkyBody(&ctx, w, h * 1.6, 0, body, isMoon ? 0.75 : 0.25, isMoon, isMoon ? 44.0 : 56.0, false, t0)
		}
		.background(Color.black)
	}
}

/// A tree design's cells as a small picture: three of them, short, middling and tall, in the colours of
/// the blocks they are made of
enum TreePreview {
	static func colour(_ k: String, _ p: ModPack, _ d: UInt32) -> UInt32 {
		if k.isEmpty { return d }
		if k.hasPrefix("tile:") {
			guard let n = Int(k.dropFirst(5)), let t = Tile(rawValue: UInt8(clampI(n, 0, 255))) else { return d }
			return t.def.colors.first ?? d
		}
		let s: (String, String) = splitModKey(k)
		if let b = p.blocks.first(where: { $0.id == s.1 }) { return ModDimPreview.averageColor(b.art) }
		return d
	}

	static func render(_ t: ModTree, _ p: ModPack) -> PixelBuf {
		let px: Int = 3
		let cellsW: Int = 3 * (treeReach * 2 + 1)
		let rows: Int = 34
		var b = PixelBuf(w: cellsW * px, h: (rows + 2) * px)
		let sky: UInt32 = 0x8AC0F0
		for i in 0..<b.px.count { b.px[i] = 0xFF000000 | sky }
		let trunk: UInt32 = colour(t.trunk, p, 0x6B4A2A)
		let branch: UInt32 = t.branch.isEmpty ? shadeRGB(trunk, 0.85) : colour(t.branch, p, trunk)
		let leaves: UInt32 = colour(t.leaves, p, 0x3E8A2E)
		let ground: UInt32 = colour(t.ground.isEmpty ? ModGround.key(.grass) : t.ground, p, 0x5DAA3A)
		func plot(_ cx: Int, _ cy: Int, _ c: UInt32) {
			if cx < 0 || cy < 0 || cx >= cellsW || cy >= rows + 2 { return }
			for y in 0..<px {
				for x in 0..<px { b.px[(cy * px + y) * b.w + cx * px + x] = 0xFF000000 | c }
			}
		}
		for x in 0..<cellsW {
			plot(x, rows, ground)
			plot(x, rows + 1, shadeRGB(ground, 0.7))
		}
		let lo: Int = clampI(t.minHeight, 1, 24)
		let hi: Int = max(lo, clampI(t.maxHeight, 1, 24))
		let heights: [Int] = [lo, (lo + hi) / 2, hi]
		for k in 0..<3 {
			let root: Int = treeReach + k * (treeReach * 2 + 1)
			let cells: [TreeCell] = TreeShapes.cells(t, heights[k], UInt64(1234 + k * 977))
			for c in cells {
				let col: UInt32 = c.part == 1 ? trunk : (c.part == 2 ? branch : leaves)
				plot(root + c.dx, rows - c.dy, col)
			}
		}
		return b
	}
}

/// Painting a tree cell by cell: empty, trunk, branch or leaves. Its root is the middle of the bottom row.
struct TreeGridEditor: View {
	@Binding var grid: ModTreeGrid
	@State var brush: Int = 3

	static let brushes: [String] = ["EMPTY", "TRUNK", "BRANCH", "LEAVES"]
	static let colours: [UInt32] = [0x1A2030, 0x7A5230, 0xA07040, 0x3E9A30]

	var body: some View {
		let g: ModTreeGrid = grid
		let cell: CGFloat = min(26, 300 / CGFloat(max(1, g.w)))
		let cw: CGFloat = cell * CGFloat(g.w)
		let ch: CGFloat = cell * CGFloat(g.h)
		return VStack(alignment: .leading, spacing: 8) {
			ChoiceRows(options: TreeGridEditor.brushes, selected: $brush, columns: 4)
			canvas(g, cell).frame(width: cw, height: ch)
			IntSlider(label: "Width", value: sizeBind(true), range: 3...15)
			IntSlider(label: "Height", value: sizeBind(false), range: 3...24)
			HStack(spacing: 8) {
				SmallButton(title: "CLEAR", color: ModUI.red) { self.clear() }
				SmallButton(title: "START FROM THE SAMPLE", color: ModUI.blue) { self.sample() }
			}
		}
	}

	func canvas(_ g: ModTreeGrid, _ cell: CGFloat) -> some View {
		let cols: [UInt32] = TreeGridEditor.colours
		return Canvas { ctx, size in
			for y in 0..<g.h {
				for x in 0..<g.w {
					let v: Int = Int(g.at(x, y))
					let r: CGRect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell - 1, height: cell - 1)
					ctx.fill(Path(r), with: .color(Color(hex: cols[clampI(v, 0, 3)])))
				}
			}
			// the root, where it stands on the ground
			let mid: CGFloat = CGFloat(g.w / 2) * cell
			ctx.fill(Path(CGRect(x: mid, y: CGFloat(g.h) * cell - 3, width: cell - 1, height: 3)), with: .color(Color(hex: 0xFFE066)))
		}
		.gesture(DragGesture(minimumDistance: 0).onChanged { (v: DragGesture.Value) in self.paint(v.location, cell) })
	}

	func paint(_ p: CGPoint, _ cell: CGFloat) {
		let x: Int = Int(floor(p.x / cell))
		let y: Int = Int(floor(p.y / cell))
		var g: ModTreeGrid = grid
		if x < 0 || y < 0 || x >= g.w || y >= g.h || !g.valid { return }
		let v: UInt8 = UInt8(clampI(brush, 0, 3))
		if g.cells[y * g.w + x] == v { return }
		g.cells[y * g.w + x] = v
		grid = g
	}

	func sizeBind(_ wide: Bool) -> Binding<Int> {
		let base: Binding<ModTreeGrid> = $grid
		return Binding<Int>(get: { wide ? base.wrappedValue.w : base.wrappedValue.h }, set: { v in
			let g: ModTreeGrid = base.wrappedValue
			if (wide ? g.w : g.h) == v { return }
			base.wrappedValue = wide ? g.resized(v, g.h) : g.resized(g.w, v)
		})
	}

	func clear() {
		var g: ModTreeGrid = grid
		g.cells = [UInt8](repeating: 0, count: g.w * g.h)
		grid = g
	}

	func sample() {
		var g: ModTreeGrid = grid
		g.cells = ModTreeGrid.sample(g.w, g.h)
		grid = g
	}
}

/// Editing one tree design: its name and shape, the blocks it is made of, its sizes and how often it grows,
/// and for a painted design the picture of it
struct TreeDesignEditor: View {
	@ObservedObject var s: ModSession
	let id: String
	var pickBlock: (String) -> Void
	var done: () -> Void

	func b<T>(_ kp: WritableKeyPath<ModTree, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.trees, id, kp, d) }
	var tree: ModTree { return s.mod.trees.first { $0.id == id } ?? ModTree() }

	static let shapeNames: [String] = ModTreeShape.allCases.map { $0.name }

	var body: some View {
		let t: ModTree = tree
		let painted: Bool = t.shape == .painted
		let pic: Image = pixImage(TreePreview.render(t, s.mod))
		return ModSection(title: t.name.uppercased(), help: "Its trunk, branches and leaves are always passed through, like the game's trees.") {
			pic.resizable().interpolation(.none).frame(width: 237, height: 150)
			ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Crystal Oak")
			Text("Shape").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			ChoiceRows(options: TreeDesignEditor.shapeNames, selected: shapeBind, columns: 3)
			blocksPart(t)
			if painted {
				TreeGridEditor(grid: b(\.grid, ModTreeGrid()))
			} else {
				sizesPart(t)
			}
			StatSlider(label: "How often it grows (among the region's designs)", value: b(\.weight, 1), range: 0.1...20.0, step: 0.1, format: "%.1f")
			SmallButton(title: "DONE", color: ModUI.accent) { self.done() }
		}
	}

	func blocksPart(_ t: ModTree) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			blockRow("Trunk", t.trunk, "trunk", "")
			blockRow("Branches", t.branch, "branch", t.branch.isEmpty ? "" : "SAME AS THE TRUNK")
			blockRow("Leaves", t.leaves, "leaves", "")
			blockRow("Grows only on", t.ground, "ground", t.ground.isEmpty ? "" : "ANY GROUND")
		}
	}

	func sizesPart(_ t: ModTree) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			IntSlider(label: "Shortest trunk", value: b(\.minHeight, 4), range: 1...24)
			IntSlider(label: "Tallest trunk", value: b(\.maxHeight, 7), range: 1...24)
			IntSlider(label: "Crown (how far the leaves reach)", value: b(\.crown, 2), range: 0...6)
			IntSlider(label: "Branches", value: b(\.branches, 1), range: 0...4)
			StatSlider(label: "Fullness of the leaves", value: b(\.density, 0.9), range: 0.2...1.0, step: 0.05, format: "%.2f")
			ModToggle(label: "A thick trunk", help: "Two blocks wide", isOn: b(\.thick, false))
		}
	}

	func blockRow(_ label: String, _ key: String, _ field: String, _ clear: String) -> some View {
		let img: Image = PatternGrid.cellImage(key, s.catalog)
		let name: String = key.isEmpty ? (field == "branch" ? "The trunk's block" : "Any") : ModGround.name(key, s.mod)
		let canClear: Bool = !clear.isEmpty
		return HStack(spacing: 10) {
			img.resizable().interpolation(.none).frame(width: 32, height: 32)
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: label).font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
				Text(verbatim: name).font(.pixel(13, .bold)).foregroundColor(Color.white)
			}
			Spacer(minLength: 0)
			if canClear { SmallButton(title: clear) { self.clearField(field) } }
			SmallButton(title: "CHOOSE", color: ModUI.blue) { self.pickBlock(field) }
		}
	}

	func clearField(_ field: String) {
		if field == "branch" { b(\.branch, "").wrappedValue = "" }
		if field == "ground" { b(\.ground, "").wrappedValue = "" }
	}

	var shapeBind: Binding<Int> {
		let base: Binding<ModTreeShape> = b(\.shape, .round)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { base.wrappedValue = ModTreeShape(rawValue: $0) ?? .round })
	}
}

struct DimensionEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var page: Int = 0
	@State var picking: String = ""
	@State var zonePick: Int = 0
	@State var preview: PixelBuf? = nil
	@State var previewOf: ModDimension? = nil
	/// which sky colour the palette sets (see skyColorNames)
	@State var skyPick: Int = 0
	/// the sun (0) or the moon (1) on the SUN & MOON page
	@State var bodyPick: Int = 0
	/// the tree design open on the TREES page
	@State var treeEdit: String = ""

	static let pages: [String] = ["BASICS", "SKY", "SUN & MOON", "LAND", "REGIONS", "TREES", "LIFE", "WAY IN", "PREVIEW"]
	static let bodyNames: [String] = ["SUN", "MOON"]
	static let skyColorNames: [String] = ["Day: top", "Day: bottom", "Night: top", "Night: bottom", "Sun"]

	func b<T>(_ kp: WritableKeyPath<ModDimension, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.dims, id, kp, d) }
	var dim: ModDimension { return s.mod.dims.first { $0.id == id } ?? ModDimension() }

	var body: some View {
		ZStack {
			VStack(spacing: 10) {
				header
				ChoiceRows(options: DimensionEditorView.pages, selected: $page, columns: 5)
				pageView
			}
		}
		.modCover(s, picking.isEmpty ? nil : picking) { self.blockPicker }
	}

	var blockPicker: some View {
		ItemPickerView(catalog: s.catalog, title: "CHOOSE A BLOCK", blocksOnly: true, pick: { (it: Item) in
			self.setBlock(self.picking, SummonRuleEditor.key(it))
			self.picking = ""
		}, cancel: { self.picking = "" })
	}

	var header: some View {
		let d: ModDimension = dim
		let way: String = d.entry.enabled ? joinText("Way in: ", d.entry.how.name.lowercased()) : "No way in yet (visit it from the Mod Test tools)"
		let col: Color = d.entry.enabled ? ModUI.gold : Color(ui: 0xFF9060)
		return HStack(spacing: 12) {
			SkySwatch(top: d.skyTop, bottom: d.skyBottom).frame(width: 64, height: 64)
			VStack(alignment: .leading, spacing: 4) {
				Text(verbatim: d.name).font(.pixel(20)).foregroundColor(Color.white)
				Text(verbatim: way).font(.pixel(11, .semibold)).foregroundColor(col)
			}
			Spacer(minLength: 0)
		}
		.padding(10)
		.background(PixelBox(color: ModUI.card))
	}

	/// The page shown: a plain switch, as the creature editor's pages (wrapping each page in AnyView
	/// crashed on the iPad)
	@ViewBuilder
	var pageView: some View {
		switch page {
		case 1: skyPage
		case 2: bodiesPage
		case 3: landPage
		case 4: zonesPage
		case 5: treesPage
		case 6: lifePage
		case 7: entryPage
		case 8: previewPage
		default: basicsPage
		}
	}

	var bodiesPage: some View {
		let d: ModDimension = dim
		let pick: Int = clampI(bodyPick, 0, 1)
		let roof: Bool = d.ceiling
		return ModSection(title: "SUN AND MOON", help: "Give the dimension a sun and a moon of its own: a picture or a round one in your colour, its size and glow, how it crosses the sky, and how much light it gives (it lights the land as the game's do).") {
			if roof { Text("This is a cavern world: it has no sky, so they are never seen.").font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xFF9060)) }
			ChoiceRows(options: DimensionEditorView.bodyNames, selected: $bodyPick, columns: 2)
			if pick == 0 {
				SkyBodyEditor(sky: b(\.sunBody, nil), moon: false, skyTop: d.skyTop, skyBottom: d.skyBottom)
			} else {
				SkyBodyEditor(sky: b(\.moonBody, nil), moon: true, skyTop: d.nightTop, skyBottom: d.nightBottom)
			}
		}
	}

	var treesPage: some View {
		let list: [ModTree] = s.mod.trees
		let editing: Bool = !treeEdit.isEmpty && list.contains { $0.id == treeEdit }
		let canAdd: Bool = list.count < ModTree.maxDesigns
		return VStack(spacing: 10) {
			Text("Tree designs belong to the whole mod: choose which grow in each region on the REGIONS page. Their trunks, branches and leaves are always passed through, like the game's trees: a solid block chosen for them grows as a pass-through form of itself (each such block uses one of a world's 64 mod block numbers).")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			if editing {
				TreeDesignEditor(s: s, id: treeEdit, pickBlock: { (f: String) in self.picking = joinText("t:", f) }, done: { self.treeEdit = "" })
			} else {
				ForEach(list) { (t: ModTree) in self.treeRow(t) }
				if canAdd { SmallButton(title: "+ TREE DESIGN", color: ModUI.accent) { self.addTree() } }
			}
		}
	}

	func treeRow(_ t: ModTree) -> some View {
		let pic: Image = pixImage(TreePreview.render(t, s.mod))
		let uses: Int = treeUses(t.id)
		let where0: String = uses == 0 ? "not grown in any region yet" : joinText("grows in ", String(uses), uses == 1 ? " region" : " regions")
		let line: String = joinText(t.shape.name, " \u{00B7} ", where0)
		return HStack(spacing: 8) {
			pic.resizable().interpolation(.none).frame(width: 111, height: 70)
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: t.name).font(.pixel(13)).foregroundColor(Color.white)
				Text(verbatim: line).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer(minLength: 0)
			SmallButton(title: "EDIT", color: ModUI.blue) { self.treeEdit = t.id }
			SmallButton(title: "\u{2715}", color: ModUI.red) { self.deleteTree(t.id) }
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	func treeUses(_ tid: String) -> Int {
		var n: Int = 0
		for d in s.mod.dims {
			for z in d.zones where z.treeKinds.contains(tid) { n += 1 }
		}
		return n
	}

	func addTree() {
		var t = ModTree()
		t.id = s.mod.freshID("tree")
		t.name = joinText("Tree ", String(s.mod.trees.count + 1))
		s.mod.trees.append(t)
		s.touch()
		treeEdit = t.id
	}

	func deleteTree(_ tid: String) {
		s.mod.trees.removeAll { $0.id == tid }
		for i in s.mod.dims.indices {
			for k in s.mod.dims[i].zones.indices { s.mod.dims[i].zones[k].treeKinds.removeAll { $0 == tid } }
		}
		s.touch()
	}

	var basicsPage: some View {
		ModSection(title: "BASICS") {
			ModTextField(label: "Name", text: b(\.name, ""), placeholder: "The Frostlands")
			ModTextField(label: "Description", text: b(\.desc, ""), placeholder: "Optional")
			ModTextField(label: "Message on arrival", text: b(\.arriveMessage, ""), placeholder: "Snow crunches underfoot.")
		}
	}

	var skyPage: some View {
		VStack(spacing: 10) {
			skySection
			lightSection
			airSection
		}
	}

	var skySection: some View {
		let pick: Int = clampI(skyPick, 0, DimensionEditorView.skyColorNames.count - 1)
		return ModSection(title: "SKY", help: "Colours at the top and the bottom of the sky, by day and by night, and the sun's. Choose one, then tap a colour.") {
			ModToggle(label: "A rock roof overhead (a cavern world)", help: "No sky, sun or rain; like the Umbral Realm", isOn: b(\.ceiling, false))
			skyPictures
			ChoiceRows(options: DimensionEditorView.skyColorNames, selected: $skyPick, columns: 5)
			ModColorRow(label: DimensionEditorView.skyColorNames[pick], color: skyColorBind(pick))
		}
	}

	/// The day sky, the night sky and the sun, as they are now
	var skyPictures: some View {
		let d: ModDimension = dim
		let sun: Color = Color(ui: d.sunColor & 0xFFFFFF)
		return HStack(alignment: .bottom, spacing: 12) {
			skyPicture("DAY", d.skyTop, d.skyBottom)
			skyPicture("NIGHT", d.nightTop, d.nightBottom)
			VStack(spacing: 2) {
				Rectangle().fill(sun).frame(width: 28, height: 28).overlay(Rectangle().stroke(Color.black, lineWidth: 1))
				Text("SUN").font(.pixel(10)).foregroundColor(ModUI.dim)
			}
		}
	}

	func skyPicture(_ name: String, _ top: UInt32, _ bottom: UInt32) -> some View {
		VStack(spacing: 2) {
			SkySwatch(top: top, bottom: bottom).frame(width: 96, height: 54)
			Text(verbatim: name).font(.pixel(10)).foregroundColor(ModUI.dim)
		}
	}

	/// The sky colour the palette sets
	func skyColorBind(_ pick: Int) -> Binding<UInt32> {
		switch pick {
		case 1: return b(\.skyBottom, 0xC07AB0)
		case 2: return b(\.nightTop, 0x080614)
		case 3: return b(\.nightBottom, 0x241A3A)
		case 4: return b(\.sunColor, 0xFFE8A0)
		default: return b(\.skyTop, 0x3A2A6A)
		}
	}

	var lightSection: some View {
		let fixed: Bool = !dim.cycle
		let word: String = timeWord(dim.fixedTime)
		return ModSection(title: "LIGHT AND TIME") {
			StatSlider(label: "Daylight", value: b(\.light, 0.8), range: 0.0...1.0, step: 0.05, format: "%.2f")
			ModToggle(label: "Day and night", help: "Off: it is always the same time there", isOn: b(\.cycle, true))
			if fixed {
				StatSlider(label: "The time it always is", value: b(\.fixedTime, 0.25), range: 0.0...1.0, step: 0.01, format: "%.2f")
				Text(verbatim: word).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			}
			ModToggle(label: "Sun", isOn: b(\.sun, true))
			ModToggle(label: "Moon", isOn: b(\.moon, true))
			ModToggle(label: "Stars", isOn: b(\.stars, true))
		}
	}

	var airSection: some View {
		ModSection(title: "AIR AND WEATHER") {
			Text("Motes in the air").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			ChoiceRows(options: ModDimText.ambients, selected: b(\.ambient, 0), columns: 6)
			Text("Weather").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			ChoiceRows(options: ModDimText.weathers, selected: b(\.weather, 0), columns: 5)
			StatSlider(label: "Cold", value: b(\.chill, 0), range: 0.0...1.0, step: 0.05, format: "%.2f")
			ModToggle(label: "Hot", isOn: b(\.hot, false))
		}
	}

	func timeWord(_ t: Double) -> String {
		if t < 0.04 || t > 0.95 { return "Dawn" }
		if t < 0.46 { return "Day" }
		if t < 0.6 { return "Dusk" }
		return "Night"
	}

	var landPage: some View {
		VStack(spacing: 10) {
			groundSection
			ModSection(title: "UNDERGROUND") {
				StatSlider(label: "Caves", value: b(\.caves, 0.4), range: 0.0...1.0, step: 0.05, format: "%.2f")
				ModToggle(label: "Pools deep in the caves", isOn: b(\.pools, true))
			}
			seaSection
			hazardSection
		}
	}

	var groundSection: some View {
		let low: Int = dim.ceiling ? 80 : 40
		let rows: ClosedRange<Int> = low...260
		let rock: String = dim.stone
		return ModSection(title: "THE GROUND", help: "Rows count down from the top of the dimension (320 rows deep).") {
			IntSlider(label: "Ground level (row)", value: b(\.surface, 150), range: rows)
			StatSlider(label: "Hills", value: b(\.hills, 12), range: 0.0...40.0, step: 1, format: "%.0f")
			StatSlider(label: "Roughness", value: b(\.roughness, 1), range: 0.2...3.0, step: 0.1, format: "%.1f")
			StatSlider(label: "Mountains", value: b(\.mountains, 0.2), range: 0.0...1.0, step: 0.05, format: "%.2f")
			blockRow("Rock", rock, "stone")
		}
	}

	var seaSection: some View {
		let seas: Bool = dim.sea > 0
		return ModSection(title: "SEAS AND SKY") {
			ModToggle(label: "Seas", isOn: seaOn)
			if seas { IntSlider(label: "Sea level (row)", value: b(\.sea, 160), range: 60...280) }
			ChoiceRows(options: ModDimText.liquids, selected: b(\.liquid, 0), columns: 2)
			StatSlider(label: "Floating islands", value: b(\.islands, 0), range: 0.0...1.0, step: 0.05, format: "%.2f")
		}
	}

	var hazardSection: some View {
		let hz: String = dim.hazard
		let has: Bool = !hz.isEmpty
		return ModSection(title: "HAZARDS", help: "A block scattered on the ground, such as spikes or one of your own.") {
			blockRow("Hazard", hz, "hazard")
			if has {
				StatSlider(label: "How often", value: b(\.hazardChance, 0.02), range: 0.0...0.3, step: 0.01, format: "%.2f")
				SmallButton(title: "NO HAZARD", color: ModUI.red) { self.setBlock("hazard", "") }
			}
		}
	}

	var seaOn: Binding<Bool> {
		let base: Binding<Int> = b(\.sea, 0)
		let surf: Int = dim.surface
		return Binding<Bool>(get: { base.wrappedValue > 0 }, set: { on in base.wrappedValue = on ? clampI(surf + 6, 60, 280) : 0 })
	}

	func blockRow(_ label: String, _ key: String, _ field: String) -> some View {
		let img: Image = PatternGrid.cellImage(key, s.catalog)
		let name: String = key.isEmpty ? "None" : ModGround.name(key, s.mod)
		return HStack(spacing: 10) {
			img.resizable().interpolation(.none).frame(width: 32, height: 32)
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: label).font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
				Text(verbatim: name).font(.pixel(13, .bold)).foregroundColor(Color.white)
			}
			Spacer(minLength: 0)
			SmallButton(title: "CHOOSE", color: ModUI.blue) { self.picking = field }
		}
	}

	/// A block chosen in the picker goes where it was asked for (a region's blocks are "z<n>:<field>",
	/// the open tree design's "t:<field>")
	func setBlock(_ field: String, _ key: String) {
		if field.hasPrefix("t:") {
			guard let ti = s.mod.trees.firstIndex(where: { $0.id == treeEdit }) else { return }
			var t: ModTree = s.mod.trees[ti]
			let part: String = String(field.dropFirst(2))
			switch part {
			case "trunk": if !key.isEmpty { t.trunk = key }
			case "branch": t.branch = key
			case "leaves": if !key.isEmpty { t.leaves = key }
			case "ground": t.ground = key
			default: break
			}
			s.mod.trees[ti] = t
			s.touch()
			return
		}
		guard let i = s.mod.dims.firstIndex(where: { $0.id == id }) else { return }
		var d: ModDimension = s.mod.dims[i]
		if field.hasPrefix("z") {
			let parts: [Substring] = field.dropFirst().split(separator: ":")
			guard parts.count == 2, let zi = Int(parts[0]), zi >= 0 && zi < d.zones.count else { return }
			switch parts[1] {
			case "ground": if !key.isEmpty { d.zones[zi].ground = key }
			case "filler": if !key.isEmpty { d.zones[zi].filler = key }
			case "plant": d.zones[zi].plant = key
			case "log": if !key.isEmpty { d.zones[zi].log = key }
			case "leaves": if !key.isEmpty { d.zones[zi].leaves = key }
			default: break
			}
		} else {
			switch field {
			case "stone": if !key.isEmpty { d.stone = key }
			case "hazard": d.hazard = key
			case "gate": d.gateBlock = key.hasPrefix("tile:") ? "" : key
			default: break
			}
		}
		s.mod.dims[i] = d
		s.touch()
	}

	func zb<T>(_ i: Int, _ kp: WritableKeyPath<ModDimZone, T>, _ d: T) -> Binding<T> {
		let base: Binding<[ModDimZone]> = b(\.zones, [])
		return Binding<T>(get: { i < base.wrappedValue.count ? base.wrappedValue[i][keyPath: kp] : d }, set: { v in
			var list: [ModDimZone] = base.wrappedValue
			if i < list.count {
				list[i][keyPath: kp] = v
				base.wrappedValue = list
			}
		})
	}

	var zonesPage: some View {
		let zones: [ModDimZone] = dim.zones
		let zi: Int = clampI(zonePick, 0, max(0, zones.count - 1))
		let names: [String] = zones.map { $0.name }
		let many: Bool = zones.count > 1
		return VStack(spacing: 10) {
			Text("Regions lie side by side, each with its own ground, plants and trees: the dimension's biomes. Each counts as one of the game's biomes for ores, structures, summoning and creature rules.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ChoiceRows(options: names, selected: $zonePick, columns: 4)
			zoneButtons(zones.count, zi)
			if zi < zones.count { zoneEditor(zi, zones[zi]) }
			if many { IntSlider(label: "Width of each region (blocks)", value: b(\.zoneWidth, 300), range: 40...2000) }
		}
	}

	func zoneButtons(_ count: Int, _ zi: Int) -> some View {
		let canAdd: Bool = count < 4
		let canDelete: Bool = count > 1
		return HStack(spacing: 8) {
			if canAdd { SmallButton(title: "+ REGION", color: ModUI.accent) { self.addZone() } }
			if canDelete { SmallButton(title: "DELETE THIS REGION", color: ModUI.red) { self.deleteZone(zi) } }
		}
	}

	func addZone() {
		var l: [ModDimZone] = dim.zones
		var z = ModDimZone()
		z.name = joinText("Region ", String(l.count + 1))
		l.append(z)
		b(\.zones, []).wrappedValue = l
		zonePick = l.count - 1
	}

	func deleteZone(_ zi: Int) {
		var l: [ModDimZone] = dim.zones
		if zi < l.count { l.remove(at: zi) }
		b(\.zones, []).wrappedValue = l
		zonePick = 0
	}

	static let biomeNames: [String] = ModBiomePicker.all.map { $0.name }

	func zoneEditor(_ zi: Int, _ z: ModDimZone) -> some View {
		let tag: String = joinText("z", String(zi), ":")
		let plants: Bool = !z.plant.isEmpty
		let trees: Bool = z.trees > 0
		return ModSection(title: z.name.uppercased()) {
			ModTextField(label: "Name", text: zb(zi, \.name, ""), placeholder: "Frozen Wastes")
			Text("Counts as").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			ChoiceRows(options: DimensionEditorView.biomeNames, selected: biomeBind(zi), columns: 5)
			blockRow("Ground", z.ground, joinText(tag, "ground"))
			blockRow("Under the ground", z.filler, joinText(tag, "filler"))
			blockRow("Plants", z.plant, joinText(tag, "plant"))
			if plants { StatSlider(label: "How many plants", value: zb(zi, \.plantChance, 0.1), range: 0.0...0.8, step: 0.02, format: "%.2f") }
			Text("Trees").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			ChoiceRows(options: ModDimText.trees, selected: zb(zi, \.trees, 1), columns: 3)
			if trees { treeKindsPart(zi, z) }
			if trees && z.treeKinds.isEmpty {
				blockRow("Trunk", z.log, joinText(tag, "log"))
				blockRow("Leaves", z.leaves, joinText(tag, "leaves"))
			}
		}
	}

	func treeKindsPart(_ zi: Int, _ z: ModDimZone) -> some View {
		let list: [ModTree] = s.mod.trees
		let none: Bool = list.isEmpty
		return VStack(alignment: .leading, spacing: 6) {
			Text("Tree designs that grow here (none chosen: simple trees of the trunk and leaves below)").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			if none {
				Text("Make designs on the TREES page.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			} else {
				PlainGrid(count: list.count, per: 3) { (i: Int) in self.treeChip(zi, z, list[i]) }
			}
		}
	}

	func treeChip(_ zi: Int, _ z: ModDimZone, _ t: ModTree) -> some View {
		let on: Bool = z.treeKinds.contains(t.id)
		return ToggleChip(title: t.name, on: on) { self.toggleTree(zi, t.id) }
	}

	func toggleTree(_ zi: Int, _ tid: String) {
		let bind: Binding<[String]> = zb(zi, \.treeKinds, [])
		var l: [String] = bind.wrappedValue
		if let k = l.firstIndex(of: tid) {
			l.remove(at: k)
		} else if l.count < ModTree.maxDesigns {
			l.append(tid)
		}
		bind.wrappedValue = l
	}

	func biomeBind(_ zi: Int) -> Binding<Int> {
		let base: Binding<Int> = zb(zi, \.biome, Biome.plains.rawValue)
		let all: [Biome] = ModBiomePicker.all
		return Binding<Int>(get: { all.firstIndex { $0.rawValue == base.wrappedValue } ?? 0 }, set: { v in base.wrappedValue = all[clampI(v, 0, all.count - 1)].rawValue })
	}

	func sp<T>(_ i: Int, _ kp: WritableKeyPath<ModDimSpawn, T>, _ d: T) -> Binding<T> {
		let base: Binding<[ModDimSpawn]> = b(\.spawns, [])
		return Binding<T>(get: { i < base.wrappedValue.count ? base.wrappedValue[i][keyPath: kp] : d }, set: { v in
			var list: [ModDimSpawn] = base.wrappedValue
			if i < list.count {
				list[i][keyPath: kp] = v
				base.wrappedValue = list
			}
		})
	}

	static let gameCreatures: [MobKind] = [.pig, .cow, .sheep, .wolf, .bat, .zombie, .skeleton, .slime, .wraith, .imp, .emberSlime, .cinderBat, .crawler, .golem]

	var creatureChoices: ([String], [String]) {
		var names: [String] = []
		var keys: [String] = []
		for m in s.mod.mobs {
			names.append(m.name)
			keys.append(s.mod.key(m.id))
		}
		for k in DimensionEditorView.gameCreatures {
			names.append(mobDef(k).name)
			keys.append(mobDef(k).name)
		}
		return (names, keys)
	}

	var lifePage: some View {
		let ch: ([String], [String]) = creatureChoices
		let n: Int = dim.spawns.count
		let canAdd: Bool = n < 8
		return VStack(spacing: 10) {
			Text("The creatures of this dimension (the game's own creatures don't come here unless you list them). Bosses are best called with a SUMMON rule that only works in this dimension.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ForEach(0..<n, id: \.self) { i in self.spawnCard(i, ch) }
			if canAdd { PixelButton(title: "+ ADD A CREATURE", color: ModUI.accent) { self.addSpawn(ch.1) } }
		}
	}

	func spawnCard(_ i: Int, _ ch: ([String], [String])) -> some View {
		let who: String = i < dim.spawns.count ? nameOf(dim.spawns[i].creature) : ""
		let title: String = joinText(String(i + 1), ". ", who)
		return VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text(verbatim: title).font(.pixel(13, .bold)).foregroundColor(Color.white)
				Spacer(minLength: 0)
				SmallButton(title: "DELETE", color: ModUI.red) { self.deleteSpawn(i) }
			}
			ChoiceRows(options: ch.0, selected: creatureBind(i, ch.1), columns: 4)
			ChoiceRows(options: ModDimText.places, selected: sp(i, \.place, 0), columns: 3)
			ChoiceRows(options: ModDimText.times, selected: sp(i, \.when, 0), columns: 3)
			StatSlider(label: "How common", value: sp(i, \.weight, 5), range: 0.1...20.0, step: 0.1, format: "%.1f")
			IntSlider(label: "Group", value: sp(i, \.group, 1), range: 1...4)
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	func deleteSpawn(_ i: Int) {
		var l: [ModDimSpawn] = dim.spawns
		if i < l.count { l.remove(at: i) }
		b(\.spawns, []).wrappedValue = l
	}

	func addSpawn(_ keys: [String]) {
		var l: [ModDimSpawn] = dim.spawns
		var n = ModDimSpawn()
		n.creature = keys.first ?? mobDef(.zombie).name
		l.append(n)
		b(\.spawns, []).wrappedValue = l
	}

	func nameOf(_ key: String) -> String {
		if let m = s.mod.mobs.first(where: { s.mod.key($0.id) == key }) { return m.name }
		return key
	}

	func creatureBind(_ i: Int, _ keys: [String]) -> Binding<Int> {
		let base: Binding<String> = sp(i, \.creature, "")
		return Binding<Int>(get: { keys.firstIndex(of: base.wrappedValue) ?? 0 }, set: { v in if !keys.isEmpty { base.wrappedValue = keys[clampI(v, 0, keys.count - 1)] } })
	}

	var entryPage: some View {
		VStack(spacing: 10) {
			ModSection(title: "THE WAY BACK") {
				ModToggle(label: "A gate where the player arrives", help: "Tapping it takes them back to where they came in", isOn: b(\.returnGate, true))
				if dim.returnGate {
					blockRow("The gate's block (one of this mod's)", dim.gateBlock, "gate")
					if dim.gateBlock.isEmpty {
						Text("None chosen: a glowing crystal.").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
					}
				}
			}
			ModSection(title: "THE WAY IN", help: "For a portal, draw a frame of your gateway block with EMPTY inside, and use a key item on it.") {
				SummonRuleEditor(s: s, rule: b(\.entry, ModDimension.defaultEntry), forDimension: true)
			}
		}
	}

	var previewPage: some View {
		VStack(spacing: 10) {
			Text("Six chunks of the dimension, from the top to the bottom, made by the same generator the game uses (a sample world). Make the preview again after changing something.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			PixelButton(title: preview == nil ? "MAKE PREVIEW" : "MAKE IT AGAIN", color: ModUI.blue) {
				preview = ModDimPreview.render(dim, s.mod)
				previewOf = dim
			}
			if let p = preview {
				pixImage(p).resizable().interpolation(.none)
					.frame(width: CGFloat(p.w) * 1.5, height: CGFloat(p.h) * 1.5)
					.background(Color.black)
				if previewOf != dim {
					Text("Changed since this preview was made.").font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xFF9060))
				}
			}
		}
	}
}

/// The dimension an ore or structure is made in: the game's two, or one of the mod's own
struct ModDimChoice: View {
	@ObservedObject var s: ModSession
	@Binding var dim: Int
	@Binding var dimKey: String

	var body: some View {
		let names: [String] = ["Overworld", "Umbral Realm"] + s.mod.dims.map { $0.name }
		let ids: [String] = s.mod.dims.map { $0.id }
		let sel: Binding<Int> = Binding<Int>(get: {
			if !dimKey.isEmpty, let i = ids.firstIndex(of: dimKey) { return 2 + i }
			return dim == 1 ? 1 : 0
		}, set: { v in
			if v >= 2 && v - 2 < ids.count {
				dimKey = ids[v - 2]
			} else {
				dimKey = ""
				dim = v == 1 ? 1 : 0
			}
		})
		return ChoiceRow(options: names, selected: sel, columns: min(5, names.count))
	}
}

/// A little square of a dimension's sky (its two colours and the step between)
struct SkySwatch: View {
	let top: UInt32
	let bottom: UInt32
	var body: some View {
		VStack(spacing: 0) {
			Rectangle().fill(Color(hex: top))
			Rectangle().fill(Color(hex: mixRGB(top, bottom, 0.5)))
			Rectangle().fill(Color(hex: bottom))
		}
	}
}

// MARK: - Mod Creator+: Logic Studio (screens)

/// Finding, changing and moving blocks inside a script. A path is a block's place: its index at the top
/// level, then for each block it sits in, which part (0 inside, 1 else) and its index there.
enum LPath {
	static func get(_ list: [LNode], _ path: [Int]) -> LNode? {
		guard let i = path.first, i >= 0, i < list.count else { return nil }
		if path.count == 1 { return list[i] }
		let rest: [Int] = Array(path.dropFirst(2))
		return path[1] == 0 ? get(list[i].body, rest) : get(list[i].alt, rest)
	}

	static func update(_ list: inout [LNode], _ path: [Int], _ f: (inout LNode) -> Void) {
		guard let i = path.first, i >= 0, i < list.count else { return }
		if path.count == 1 {
			f(&list[i])
			return
		}
		if path.count < 3 { return }
		let rest: [Int] = Array(path.dropFirst(2))
		if path[1] == 0 { update(&list[i].body, rest, f) } else { update(&list[i].alt, rest, f) }
	}

	/// the list a block sits in, changed by f
	static func updateList(_ list: inout [LNode], _ parent: [Int], _ f: (inout [LNode]) -> Void) {
		if parent.isEmpty {
			f(&list)
			return
		}
		let container: [Int] = Array(parent.dropLast())
		let br: Int = parent.last ?? 0
		update(&list, container) { n in
			if br == 0 { f(&n.body) } else { f(&n.alt) }
		}
	}

	static func remove(_ list: inout [LNode], _ path: [Int]) {
		guard let i = path.last else { return }
		updateList(&list, Array(path.dropLast())) { l in if i >= 0 && i < l.count { l.remove(at: i) } }
	}

	static func move(_ list: inout [LNode], _ path: [Int], _ d: Int) {
		guard let i = path.last else { return }
		updateList(&list, Array(path.dropLast())) { l in
			let j: Int = i + d
			if i >= 0 && i < l.count && j >= 0 && j < l.count { l.swapAt(i, j) }
		}
	}

	/// `into` is a block's path and a part (0 inside, 1 else); nil adds to the end of the script
	static func insert(_ list: inout [LNode], _ into: [Int]?, _ node: LNode) {
		guard let p = into, p.count >= 2 else {
			list.append(node)
			return
		}
		updateList(&list, p) { l in l.append(node) }
	}

	static func exprUpdate(_ e: inout LExpr, _ path: [Int], _ f: (inout LExpr) -> Void) {
		if path.isEmpty {
			f(&e)
			return
		}
		let i: Int = path[0]
		if i < 0 || i >= e.args.count { return }
		exprUpdate(&e.args[i], Array(path.dropFirst()), f)
	}
}

/// The LOGIC STUDIO tab: the mod's variables and scripts (optional: everything else works without it)
struct LogicStudioView: View {
	@ObservedObject var s: ModSession
	var open: (String) -> Void
	@State var newVar: String = ""

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Optional. Every part of the Mod Creator works without scripts. Scripts are stacks of blocks run by the game's own safe interpreter: they can only use the blocks shown here, loops that go on must wait, and nothing outside the game can be reached.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			variablesSection
			addRow
			ForEach(s.mod.scripts) { sc in self.scriptRow(sc) }
		}
	}

	var variablesSection: some View {
		let vars: [String] = s.mod.variables
		let room: Bool = vars.count < LLimits.maxVariables
		return ModSection(title: "VARIABLES", help: "Numbers your scripts keep, one set per world (saved with it).") {
			ForEach(vars, id: \.self) { v in self.variableRow(v) }
			if room {
				HStack(spacing: 8) {
					ModTextField(label: "New variable", text: $newVar, placeholder: "score")
					SmallButton(title: "+ ADD", color: ModUI.accent) { self.addVariable() }
				}
			}
		}
	}

	func variableRow(_ v: String) -> some View {
		HStack {
			Text(verbatim: v).font(.pixel(13, .bold)).foregroundColor(Color.white)
			Spacer(minLength: 0)
			SmallButton(title: "DELETE", color: ModUI.red) { self.deleteVariable(v) }
		}
	}

	func deleteVariable(_ v: String) {
		s.mod.variables.removeAll { $0 == v }
		s.touch()
	}

	func addVariable() {
		let n: String = String(newVar.trimmingCharacters(in: .whitespaces).prefix(20))
		if !n.isEmpty && !s.mod.variables.contains(n) {
			s.mod.variables.append(n)
			s.touch()
		}
		newVar = ""
	}

	var addRow: some View {
		let room: Bool = s.mod.scripts.count < LLimits.maxScripts
		return HStack(spacing: 8) {
			if room {
				PixelButton(title: "+ NEW SCRIPT", color: ModUI.accent) { self.add(.worldStart) }
				PixelButton(title: "+ NEW GROUP", color: Color(ui: 0x8A6A2A)) { self.add(.group) }
			}
		}
	}

	func scriptRow(_ sc: ModScript) -> some View {
		let bar: Color = Color(ui: sc.event == .group ? 0xC08A3A : 0xE8C040)
		let nameCol: Color = sc.enabled ? Color.white : ModUI.dim
		let blocks: String = String(LogicStudioView.count(sc.blocks))
		let line: String = joinText(sc.event.name, " \u{00B7} ", blocks, " blocks", sc.enabled ? "" : " \u{00B7} off")
		return Button(action: { self.open(sc.id) }) {
			HStack(spacing: 10) {
				Rectangle().fill(bar).frame(width: 10, height: 44)
				VStack(alignment: .leading, spacing: 3) {
					Text(verbatim: sc.name).font(.pixel(14)).foregroundColor(nameCol)
					Text(verbatim: line).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
				}
				Spacer(minLength: 0)
			}
			.padding(8)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(PixelBox(color: ModUI.card))
		}
		.buttonStyle(.plain)
	}

	static func count(_ l: [LNode]) -> Int {
		var n: Int = 0
		for b in l { n += 1 + count(b.body) + count(b.alt) }
		return n
	}

	func add(_ e: LEvent) {
		var sc = ModScript()
		sc.id = s.mod.freshID("sc")
		sc.event = e
		let number: String = String(s.mod.scripts.count + 1)
		let word: String = e == .group ? "Group " : "Script "
		sc.name = joinText(word, number)
		if e == .worldStart {
			var hi = LNode(.say)
			hi.s = "My mod is on!"
			sc.blocks = [hi]
		}
		s.mod.scripts.append(sc)
		s.touch()
		open(sc.id)
	}
}

/// Editing one script, Scratch-style: what starts it (the hat), then its blocks. Tap a block in the
/// palette to add it at the end, or inside the block chosen with IN.
struct ScriptEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var cat: Int = 0
	/// where new blocks go: a block's path and part, or nil for the end of the script
	@State var into: [Int]? = nil
	@State var exprPick: ([Int], Int, [Int])? = nil
	@State var itemPick: [Int]? = nil
	@State var exprItemPick: ([Int], Int, [Int])? = nil
	@State var blockPick: [Int]? = nil

	var script: ModScript { return s.mod.scripts.first { $0.id == id } ?? ModScript() }
	func b<T>(_ kp: WritableKeyPath<ModScript, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.scripts, id, kp, d) }

	var body: some View {
		ZStack {
			VStack(alignment: .leading, spacing: 10) {
				hat
				palette
				whereNote
				blockList(script.blocks, [])
				if script.blocks.isEmpty {
					Text("No blocks yet: tap one in the palette above.").font(.pixel(12)).foregroundColor(ModUI.dim)
				}
				issues
			}
		}
		.modCover(s, coverKey) { self.overlay }
	}

	/// which picker is open (nil: none)
	var coverKey: Int? {
		if exprPick != nil { return 1 }
		if itemPick != nil { return 2 }
		if exprItemPick != nil { return 3 }
		if blockPick != nil { return 4 }
		return nil
	}

	var whereNote: some View {
		let atEnd: Bool = into == nil
		let text: String = atEnd ? "New blocks go at the end of the script." : joinText("New blocks go inside \u{201C}", intoTitle, "\u{201D}.")
		return VStack(alignment: .leading, spacing: 6) {
			Text(verbatim: text).font(.pixel(11, .bold)).foregroundColor(ModUI.gold)
			if !atEnd { SmallButton(title: "ADD AT THE END INSTEAD", color: ModUI.blue) { self.into = nil } }
		}
	}

	/// The picker that is open, if any
	var overlay: AnyView {
		if let ep = exprPick { return AnyView(reporterPicker(ep)) }
		if let ip = itemPick { return AnyView(itemPicker(ip)) }
		if let ep = exprItemPick { return AnyView(exprItemPicker(ep)) }
		if let bp = blockPick { return AnyView(blockPicker(bp)) }
		return AnyView(EmptyView())
	}

	func reporterPicker(_ ep: ([Int], Int, [Int])) -> some View {
		ReporterPicker(s: s, pick: { (e: LExpr) in
			self.setExpr(ep.0, ep.1, ep.2) { $0 = e }
			self.exprPick = nil
		}, cancel: { self.exprPick = nil })
	}

	func itemPicker(_ ip: [Int]) -> some View {
		ItemPickerView(catalog: s.catalog, title: "CHOOSE AN ITEM", pick: { (it: Item) in
			self.edit(ip) { $0.item = it }
			self.itemPick = nil
		}, cancel: { self.itemPick = nil })
	}

	func exprItemPicker(_ ep: ([Int], Int, [Int])) -> some View {
		ItemPickerView(catalog: s.catalog, title: "CHOOSE AN ITEM", pick: { (it: Item) in
			self.setExpr(ep.0, ep.1, ep.2) { $0.item = it }
			self.exprItemPick = nil
		}, cancel: { self.exprItemPick = nil })
	}

	func blockPicker(_ bp: [Int]) -> some View {
		ItemPickerView(catalog: s.catalog, title: "CHOOSE A BLOCK", blocksOnly: true, pick: { (it: Item) in
			let k: String = SummonRuleEditor.key(it)
			self.edit(bp) { $0.s = k }
			self.blockPick = nil
		}, cancel: { self.blockPick = nil })
	}

	var intoTitle: String {
		guard let p = into, p.count >= 2, let n = LPath.get(script.blocks, Array(p.dropLast())) else { return "the script" }
		return LSpec.of(n.op).title + (p.last == 1 ? " (else)" : "")
	}

	// MARK: the hat block

	var hat: some View {
		let sc: ModScript = script
		let group: Bool = sc.event == .group
		let bg: Color = Color(ui: group ? 0xC08A3A : 0xE8C040)
		return VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Boss rage")
				ModToggle(label: "On", isOn: b(\.enabled, true))
			}
			if group { groupInputs } else { eventPart(sc) }
		}
		.padding(10)
		.background(bg)
		.cornerRadius(10)
	}

	var groupInputs: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("A GROUP: other scripts run it with \u{201C}run a group\u{201D}, giving it up to three inputs (read them with \u{201C}group input\u{201D}).")
				.font(.pixel(11, .semibold)).foregroundColor(Color.black)
			ForEach(0..<3, id: \.self) { k in self.inputField(k) }
		}
	}

	func inputField(_ k: Int) -> ModTextField {
		let label: String = joinText("Input ", String(k + 1))
		let hint: String = k == 0 ? "damage" : ""
		return ModTextField(label: label, text: paramBind(k), placeholder: hint)
	}

	static let eventList: [LEvent] = LEvent.allCases.filter { $0 != .group }
	static let eventNames: [String] = ScriptEditorView.eventList.map { $0.name }

	func eventPart(_ sc: ModScript) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("WHEN").font(.pixel(12, .bold)).foregroundColor(Color.black)
			ChoiceRow(options: ScriptEditorView.eventNames, selected: eventBind, columns: 2)
			eventDetail(sc)
			eventTarget(sc)
		}
	}

	var eventBind: Binding<Int> {
		let base: Binding<LEvent> = b(\.event, .worldStart)
		let list: [LEvent] = LEvent.allCases.filter { $0 != .group }
		return Binding<Int>(get: { list.firstIndex(of: base.wrappedValue) ?? 0 }, set: { base.wrappedValue = list[clampI($0, 0, list.count - 1)] })
	}

	func paramBind(_ k: Int) -> Binding<String> {
		let base: Binding<[String]> = b(\.params, [])
		return Binding<String>(get: { k < base.wrappedValue.count ? base.wrappedValue[k] : "" }, set: { v in
			var l: [String] = base.wrappedValue
			while l.count <= k { l.append("") }
			l[k] = String(v.prefix(16))
			base.wrappedValue = l
		})
	}

	func eventDetail(_ sc: ModScript) -> AnyView {
		switch sc.event {
		case .every, .creatureEvery:
			return AnyView(StatSlider(label: "Seconds between", value: b(\.ev, 5), range: 0.25...120.0, step: 0.25, format: "%.2f", unit: " s"))
		case .phase:
			return AnyView(StatSlider(label: "Phase", value: b(\.ev, 1), range: 1.0...6.0, step: 1, format: "%.0f"))
		case .channelOn:
			return AnyView(StatSlider(label: "Channel", value: b(\.ev, 1), range: 1.0...8.0, step: 1, format: "%.0f"))
		case .custom:
			return AnyView(ModTextField(label: "Message name", text: b(\.evText, ""), placeholder: "open the gate"))
		case .enterDim:
			let names: [String] = ["Any dimension"] + s.mod.dims.map { $0.name }
			return AnyView(ChoiceRow(options: names, selected: dimEventBind, columns: 3))
		default:
			return AnyView(EmptyView())
		}
	}

	func eventTarget(_ sc: ModScript) -> AnyView {
		var opts: [(String, String)] = []
		var label: String = ""
		switch sc.event.subject {
		case 1:
			label = "Which creature"
			for m in s.mod.mobs { opts.append((m.name, s.mod.key(m.id))) }
		case 2:
			label = "Which item"
			for m in s.mod.items { opts.append((m.name, s.mod.key(m.id))) }
		case 3:
			label = "Which block"
			for m in s.mod.blocks { opts.append((m.name, s.mod.key(m.id))) }
		default:
			return AnyView(EmptyView())
		}
		return AnyView(targetRow(label, opts))
	}

	var dimEventBind: Binding<Int> {
		let base: Binding<String> = b(\.evText, "")
		let keys: [String] = [""] + s.mod.dims.map { s.mod.key($0.id) }
		return Binding<Int>(get: { keys.firstIndex(of: base.wrappedValue) ?? 0 }, set: { base.wrappedValue = keys[clampI($0, 0, keys.count - 1)] })
	}

	func targetRow(_ label: String, _ opts: [(String, String)]) -> some View {
		let base: Binding<String> = b(\.target, "")
		let keys: [String] = opts.map { $0.1 }
		let sel: Binding<Int> = Binding<Int>(get: { keys.firstIndex(of: base.wrappedValue) ?? -1 }, set: { v in if !keys.isEmpty { base.wrappedValue = keys[clampI(v, 0, keys.count - 1)] } })
		return VStack(alignment: .leading, spacing: 4) {
			Text(verbatim: label).font(.pixel(11, .bold)).foregroundColor(Color.black)
			if opts.isEmpty {
				Text("Make one in this mod first.").font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0x7A1A1A))
			} else {
				ChoiceRow(options: opts.map { $0.0 }, selected: sel, columns: 3)
			}
		}
	}

	// MARK: the palette

	static let catNames: [String] = LCat.allCases.map { $0.name }

	var palette: some View {
		let cats: [LCat] = LCat.allCases
		let c: LCat = cats[clampI(cat, 0, cats.count - 1)]
		let specs: [LSpec] = LSpec.all.filter { $0.cat == c }
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 150), spacing: 6)]
		let col: Color = Color(ui: c.color)
		return VStack(alignment: .leading, spacing: 6) {
			ChoiceRow(options: ScriptEditorView.catNames, selected: $cat, columns: 4)
			LazyVGrid(columns: cols, spacing: 6) {
				ForEach(0..<specs.count, id: \.self) { k in self.paletteButton(specs[k], col) }
			}
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	func paletteButton(_ sp: LSpec, _ col: Color) -> some View {
		Button(action: { self.addBlock(sp.op) }) {
			Text(verbatim: sp.title).font(.pixel(11, .bold)).foregroundColor(Color.white)
				.multilineTextAlignment(.center)
				.frame(maxWidth: .infinity, minHeight: 44)
				.background(col)
				.cornerRadius(8)
		}
		.buttonStyle(.plain)
	}

	func addBlock(_ op: LOp) {
		var list: [LNode] = script.blocks
		if LogicStudioView.count(list) >= LLimits.maxBlocks { return }
		LPath.insert(&list, into, LNode(op))
		b(\.blocks, []).wrappedValue = list
	}

	// MARK: the script

	func blockList(_ list: [LNode], _ base: [Int]) -> AnyView {
		return AnyView(VStack(alignment: .leading, spacing: 4) {
			ForEach(0..<list.count, id: \.self) { i in
				self.blockRow(list[i], base + [i])
			}
		})
	}

	func blockRow(_ n: LNode, _ path: [Int]) -> AnyView {
		let sp: LSpec = LSpec.of(n.op)
		let col: Color = Color(ui: sp.cat.color)
		return AnyView(VStack(alignment: .leading, spacing: 6) {
			rowHeader(sp, path)
			fields(n, path, sp)
			if sp.inside >= 1 { inner(n.body, path + [0], col, "(empty: choose IN, then add blocks)") }
			if sp.inside == 2 {
				Text("else").font(.pixel(12, .bold)).foregroundColor(Color.white)
				inner(n.alt, path + [1], col, "(empty: choose ELSE, then add blocks)")
			}
		}
		.padding(8)
		.background(col.opacity(0.92))
		.cornerRadius(8))
	}

	func rowHeader(_ sp: LSpec, _ path: [Int]) -> some View {
		let dark: Color = Color.black.opacity(0.35)
		let inTitle: String = isInto(path, 0) ? "IN \u{2713}" : "IN"
		let elseTitle: String = isInto(path, 1) ? "ELSE \u{2713}" : "ELSE"
		let hasIn: Bool = sp.inside >= 1
		let hasElse: Bool = sp.inside == 2
		return HStack(spacing: 6) {
			Text(verbatim: sp.title).font(.pixel(13, .bold)).foregroundColor(Color.white)
			Spacer(minLength: 0)
			if hasIn { SmallButton(title: inTitle, color: dark) { self.into = path + [0] } }
			if hasElse { SmallButton(title: elseTitle, color: dark) { self.into = path + [1] } }
			SmallButton(title: "\u{2191}", color: dark) { self.moveBlock(path, -1) }
			SmallButton(title: "\u{2193}", color: dark) { self.moveBlock(path, 1) }
			SmallButton(title: "\u{2715}", color: ModUI.red) { self.removeBlock(path) }
		}
	}

	func inner(_ list: [LNode], _ path: [Int], _ col: Color, _ empty: String) -> some View {
		let none: Bool = list.isEmpty
		return HStack(alignment: .top, spacing: 6) {
			Rectangle().fill(col).frame(width: 8)
			VStack(alignment: .leading, spacing: 4) {
				blockList(list, path)
				if none { Text(verbatim: empty).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.8)) }
			}
		}
	}

	func moveBlock(_ path: [Int], _ d: Int) {
		mutate { LPath.move(&$0, path, d) }
	}

	func removeBlock(_ path: [Int]) {
		if let p = into, p.starts(with: path) { into = nil }
		mutate { LPath.remove(&$0, path) }
	}

	func isInto(_ path: [Int], _ part: Int) -> Bool { return into == path + [part] }

	func mutate(_ f: (inout [LNode]) -> Void) {
		var list: [LNode] = script.blocks
		f(&list)
		b(\.blocks, []).wrappedValue = list
	}

	func edit(_ path: [Int], _ f: (inout LNode) -> Void) {
		mutate { LPath.update(&$0, path, f) }
	}

	func setExpr(_ path: [Int], _ arg: Int, _ sub: [Int], _ f: (inout LExpr) -> Void) {
		edit(path) { n in
			while n.args.count <= arg { n.args.append(LExpr(0)) }
			LPath.exprUpdate(&n.args[arg], sub, f)
		}
	}

	// MARK: a block's inputs

	func fields(_ n: LNode, _ path: [Int], _ sp: LSpec) -> AnyView {
		return AnyView(VStack(alignment: .leading, spacing: 4) {
			ForEach(0..<sp.fields.count, id: \.self) { k in
				self.field(n, path, sp.fields[k])
			}
		})
	}

	func field(_ n: LNode, _ path: [Int], _ f: LField) -> AnyView {
		switch f.kind {
		case .number:
			return AnyView(LNumBox(label: f.label, value: numBind(path, f.slot), lo: f.lo, hi: f.hi))
		case .text:
			return AnyView(ModTextField(label: f.label, text: strBind(path), placeholder: ""))
		case .choice:
			let names: [String] = ScriptEditorView.choiceNames(f.list)
			return labelled(f.label, AnyView(ChoiceRow(options: names, selected: choiceBind(path, f.slot), columns: 4)))
		case .item:
			return itemField(n, path, f.label)
		case .key:
			return keyField(n, path, f)
		case .expr:
			let e: LExpr = f.slot < n.args.count ? n.args[f.slot] : LExpr(0)
			return AnyView(HStack(spacing: 6) {
				Text(verbatim: f.label).font(.pixel(10, .bold)).foregroundColor(Color.white.opacity(0.85))
				exprView(e, path, f.slot, [])
			})
		}
	}

	/// A small label above an input
	func labelled(_ label: String, _ content: AnyView) -> AnyView {
		return AnyView(VStack(alignment: .leading, spacing: 2) {
			Text(verbatim: label).font(.pixel(10, .bold)).foregroundColor(Color.white.opacity(0.85))
			content
		})
	}

	func choiceBind(_ path: [Int], _ slot: Int) -> Binding<Int> {
		return Binding<Int>(get: { Int(self.num(path, slot)) }, set: { (v: Int) in
			let d: Double = Double(v)
			self.edit(path) { n in
				if slot == 0 { n.a = d } else if slot == 1 { n.b = d } else { n.c = d }
			}
		})
	}

	func itemField(_ n: LNode, _ path: [Int], _ label: String) -> AnyView {
		let name: String = n.item.map { ModPreview.name($0, s.catalog) } ?? "none"
		let line: String = joinText(label, ": ", name)
		return AnyView(HStack(spacing: 8) {
			Text(verbatim: line).font(.pixel(11, .bold)).foregroundColor(Color.white)
			SmallButton(title: "CHOOSE", color: Color.black.opacity(0.35)) { self.itemPick = path }
		})
	}

	func num(_ path: [Int], _ slot: Int) -> Double {
		guard let n = LPath.get(script.blocks, path) else { return 0 }
		return slot == 0 ? n.a : (slot == 1 ? n.b : n.c)
	}

	func numBind(_ path: [Int], _ slot: Int) -> Binding<Double> {
		return Binding<Double>(get: { self.num(path, slot) }, set: { v in self.edit(path) { n in
			if slot == 0 { n.a = v } else if slot == 1 { n.b = v } else { n.c = v }
		} })
	}

	func strBind(_ path: [Int]) -> Binding<String> {
		return Binding<String>(get: { LPath.get(self.script.blocks, path)?.s ?? "" }, set: { v in self.edit(path) { $0.s = String(v.prefix(80)) } })
	}

	static func choiceNames(_ list: Int) -> [String] {
		switch list {
		case 0: return LReporters.soundNames
		case 1: return ModEffectKind.allCases.map { $0.name }
		default: return ModGameShots.names
		}
	}

	func keyField(_ n: LNode, _ path: [Int], _ f: LField) -> AnyView {
		switch f.list {
		case 1: return blockField(n, path, f.label)
		case 3: return AnyView(ModTextField(label: f.label, text: strBind(path), placeholder: "open the gate"))
		default: break
		}
		let opts: ([String], [String]) = keyOptions(f.list)
		if opts.0.isEmpty {
			let what: String = ScriptEditorView.missingWhat(f.list)
			let line: String = joinText(f.label, ": ", what)
			return AnyView(Text(verbatim: line).font(.pixel(10, .semibold)).foregroundColor(Color.white))
		}
		return labelled(f.label, AnyView(ChoiceRow(options: opts.0, selected: keyBind(path, opts.1), columns: 4)))
	}

	static func missingWhat(_ list: Int) -> String {
		if list == 4 { return "Add a variable in the Logic Studio list first." }
		if list == 5 { return "Make a group first (+ NEW GROUP)." }
		return "Make one in this mod first."
	}

	/// What a key input may be set to: (names, keys)
	func keyOptions(_ list: Int) -> ([String], [String]) {
		var names: [String] = []
		var keys: [String] = []
		switch list {
		case 0:
			for m in s.mod.mobs {
				names.append(m.name)
				keys.append(s.mod.key(m.id))
			}
			for k in ScriptEditorView.gameCreatures {
				names.append(mobDef(k).name)
				keys.append(mobDef(k).name)
			}
		case 2:
			names.append("Game shot")
			keys.append("")
			for p in s.mod.projectiles {
				names.append(p.name)
				keys.append(s.mod.key(p.id))
			}
		case 4:
			for v in s.mod.variables {
				names.append(v)
				keys.append(v)
			}
		case 5:
			for g in s.mod.scripts where g.event == .group && g.id != id {
				names.append(g.name)
				keys.append(s.mod.key(g.id))
			}
		default:
			for d in s.mod.dims {
				names.append(d.name)
				keys.append(s.mod.key(d.id))
			}
		}
		return (names, keys)
	}

	static let gameCreatures: [MobKind] = BossPhasesPage.gameHelpers + [MobKind.pig, .cow, .wolf]

	func keyBind(_ path: [Int], _ keys: [String]) -> Binding<Int> {
		return Binding<Int>(get: {
			let cur: String = LPath.get(self.script.blocks, path)?.s ?? ""
			return keys.firstIndex(of: cur) ?? -1
		}, set: { (v: Int) in
			let k: String = keys[clampI(v, 0, keys.count - 1)]
			self.edit(path) { $0.s = k }
		})
	}

	func blockField(_ n: LNode, _ path: [Int], _ label: String) -> AnyView {
		let name: String = n.s.isEmpty ? "none" : ModGround.name(n.s, s.mod)
		let line: String = joinText(label, ": ", name)
		return AnyView(HStack(spacing: 8) {
			Text(verbatim: line).font(.pixel(11, .bold)).foregroundColor(Color.white)
			SmallButton(title: "CHOOSE", color: Color.black.opacity(0.35)) { self.blockPick = path }
		})
	}

	// MARK: values

	/// A value as a chip: a number to type, or a reporter (tap its name to swap it for another) with
	/// its own inputs inside
	func exprView(_ e: LExpr, _ path: [Int], _ arg: Int, _ sub: [Int]) -> AnyView {
		if e.op == .num { return numberChip(e, path, arg, sub) }
		return AnyView(HStack(spacing: 4) {
			reporterButton(e.op, path, arg, sub)
			exprDetail(e, path, arg, sub)
			ForEach(0..<e.args.count, id: \.self) { k in self.exprView(e.args[k], path, arg, sub + [k]) }
		}
		.padding(4)
		.background(Color.black.opacity(0.2))
		.cornerRadius(10))
	}

	func numberChip(_ e: LExpr, _ path: [Int], _ arg: Int, _ sub: [Int]) -> AnyView {
		let vb: Binding<Double> = exprNum(e.v, path, arg, sub)
		return AnyView(HStack(spacing: 4) {
			LNumBox(label: "", value: vb, lo: -100000, hi: 100000, compact: true)
			SmallButton(title: "\u{25BE}", color: Color.black.opacity(0.35)) { self.exprPick = (path, arg, sub) }
		}
		.padding(4)
		.background(Color.white.opacity(0.25))
		.cornerRadius(10))
	}

	func reporterButton(_ op: LEOp, _ path: [Int], _ arg: Int, _ sub: [Int]) -> some View {
		Button(action: { self.exprPick = (path, arg, sub) }) {
			Text(verbatim: LReporters.name(op)).font(.pixel(11, .bold)).foregroundColor(Color.black)
				.padding(.horizontal, 8)
				.frame(minHeight: 34)
				.background(Color(ui: 0x9AE070))
				.cornerRadius(10)
		}
		.buttonStyle(.plain)
	}

	/// A value's number, read and set through its place in the script
	func exprNum(_ cur: Double, _ path: [Int], _ arg: Int, _ sub: [Int]) -> Binding<Double> {
		return Binding<Double>(get: { cur }, set: { (v: Double) in self.setExpr(path, arg, sub) { $0.v = v } })
	}

	/// A value's choice among keys, read and set through its place in the script
	func exprKey(_ cur: String, _ keys: [String], _ path: [Int], _ arg: Int, _ sub: [Int]) -> Binding<Int> {
		return Binding<Int>(get: { keys.firstIndex(of: cur) ?? -1 }, set: { (v: Int) in
			let k: String = keys[clampI(v, 0, keys.count - 1)]
			self.setExpr(path, arg, sub) { $0.s = k }
		})
	}

	/// The setting a reporter needs (which variable, input, item, distance, dimension or biome)
	func exprDetail(_ e: LExpr, _ path: [Int], _ arg: Int, _ sub: [Int]) -> AnyView {
		switch e.op {
		case .variable:
			let vars: [String] = s.mod.variables
			if vars.isEmpty { return AnyView(Text("(no variables)").font(.pixel(10)).foregroundColor(Color.white)) }
			let cols: Int = min(4, vars.count)
			return AnyView(ChoiceRow(options: vars, selected: exprKey(e.s, vars, path, arg, sub), columns: cols).frame(maxWidth: 360))
		case .param:
			return AnyView(LNumBox(label: "", value: exprNum(e.v, path, arg, sub), lo: 1, hi: 3, compact: true))
		case .nearby:
			return AnyView(HStack(spacing: 2) {
				LNumBox(label: "", value: exprNum(e.v, path, arg, sub), lo: 1, hi: 30, compact: true)
				Text("blocks").font(.pixel(10)).foregroundColor(Color.white)
			})
		case .channel:
			return AnyView(LNumBox(label: "", value: exprNum(e.v, path, arg, sub), lo: 1, hi: 8, compact: true))
		case .itemCount:
			let name: String = e.item.map { ModPreview.name($0, s.catalog) } ?? "CHOOSE ITEM"
			return AnyView(SmallButton(title: name, color: Color.black.opacity(0.35)) { self.exprItemPick = (path, arg, sub) })
		case .inDim:
			let keys: [String] = ["overworld", "umbral"] + s.mod.dims.map { s.mod.key($0.id) }
			let names: [String] = ["Overworld", "Umbral Realm"] + s.mod.dims.map { $0.name }
			return AnyView(ChoiceRow(options: names, selected: exprKey(e.s, keys, path, arg, sub), columns: 3).frame(maxWidth: 360))
		case .inBiome:
			return biomeChoice(e, path, arg, sub)
		default:
			return AnyView(EmptyView())
		}
	}

	func biomeChoice(_ e: LExpr, _ path: [Int], _ arg: Int, _ sub: [Int]) -> AnyView {
		let all: [Biome] = ModBiomePicker.all
		let cur: Int = Int(e.v)
		let sel: Binding<Int> = Binding<Int>(get: { all.firstIndex { $0.rawValue == cur } ?? -1 }, set: { (v: Int) in
			let raw: Double = Double(all[clampI(v, 0, all.count - 1)].rawValue)
			self.setExpr(path, arg, sub) { $0.v = raw }
		})
		return AnyView(ChoiceRow(options: DimensionEditorView.biomeNames, selected: sel, columns: 5).frame(maxWidth: 420))
	}

	/// What the checks found in this script
	var issues: some View {
		let place: String = joinText("Script \u{201C}", script.name, "\u{201D}")
		let mine: [ModIssue] = s.report.issues.filter { $0.place == place }
		return VStack(alignment: .leading, spacing: 4) {
			if !mine.isEmpty {
				Text("CHECKS").font(.pixel(12, .bold)).foregroundColor(ModUI.gold)
				ForEach(mine) { i in
					Text(verbatim: joinText("\u{2022} ", i.text)).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xFFB070))
				}
			}
		}
	}
}

/// A number with big minus and plus buttons (and typing)
struct LNumBox: View {
	let label: String
	@Binding var value: Double
	let lo: Double
	let hi: Double
	var compact: Bool = false

	var step: Double { return hi - lo <= 2.01 ? 0.05 : (hi - lo <= 20.01 ? 0.5 : 1) }

	var text: Binding<String> {
		return Binding<String>(get: {
			let v: Double = value
			return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
		}, set: { t in
			if let v = Double(t.trimmingCharacters(in: .whitespaces)) { value = clampD(v, lo, hi) }
		})
	}

	var body: some View {
		HStack(spacing: 4) {
			if !label.isEmpty { Text(verbatim: label).font(.pixel(10, .bold)).foregroundColor(Color.white.opacity(0.85)) }
			SmallButton(title: "\u{2212}", color: Color.black.opacity(0.35)) { value = clampD(value - step, lo, hi) }
			TextField("0", text: text)
				.font(.pixel(13, .bold))
				.foregroundColor(Color.white)
				.frame(width: compact ? 64 : 80)
				.padding(4)
				.background(Color.black.opacity(0.35))
			SmallButton(title: "+", color: Color.black.opacity(0.35)) { value = clampD(value + step, lo, hi) }
		}
	}
}

/// Choosing a reporter for a value
struct ReporterPicker: View {
	@ObservedObject var s: ModSession
	var pick: (LExpr) -> Void
	var cancel: () -> Void

	static let groups: [(String, [LEOp])] = [
		("NUMBERS", [.num, .random, .variable, .param]),
		("MATHS", [.add, .sub, .mul, .div, .mod]),
		("TESTS", [.lt, .gt, .eq, .and, .or, .not]),
		("THE PLAYER", [.playerHP, .playerMaxHP, .playerX, .playerY, .itemCount, .distance]),
		("MY CREATURE OR BLOCK", [.selfHP, .selfHPPct, .selfX, .selfY, .nearby]),
		("THE WORLD", [.timeOfDay, .isNight, .raining, .inDim, .inBiome, .channel]),
	]

	var body: some View {
		ZStack {
			Color.black.opacity(0.7).ignoresSafeArea()
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text("CHOOSE A VALUE").font(.pixel(18)).foregroundColor(ModUI.gold)
					Spacer()
					SmallButton(title: "CANCEL", color: ModUI.red) { self.cancel() }
				}
				ScrollView {
					VStack(alignment: .leading, spacing: 8) {
						ForEach(0..<ReporterPicker.groups.count, id: \.self) { g in self.group(g) }
					}
				}
			}
			.padding(14)
			.frame(maxWidth: 820, maxHeight: 640)
			.background(PixelBox(color: ModUI.panel))
			.padding(10)
		}
	}

	func group(_ g: Int) -> some View {
		let title: String = ReporterPicker.groups[g].0
		let ops: [LEOp] = ReporterPicker.groups[g].1
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 150), spacing: 6)]
		return VStack(alignment: .leading, spacing: 6) {
			Text(verbatim: title).font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			LazyVGrid(columns: cols, spacing: 6) {
				ForEach(0..<ops.count, id: \.self) { k in self.opButton(ops[k]) }
			}
		}
	}

	func opButton(_ op: LEOp) -> some View {
		Button(action: { self.pick(ReporterPicker.make(op)) }) {
			Text(verbatim: LReporters.name(op)).font(.pixel(11, .bold)).foregroundColor(Color.black)
				.frame(maxWidth: .infinity, minHeight: 44)
				.background(Color(ui: 0x9AE070))
				.cornerRadius(10)
		}
		.buttonStyle(.plain)
	}

	static func make(_ op: LEOp) -> LExpr {
		var e = LExpr(op: op)
		for _ in 0..<LReporters.arity(op) { e.args.append(LExpr(0)) }
		if op == .param { e.v = 1 }
		if op == .nearby { e.v = 6 }
		if op == .channel { e.v = 1 }
		if op == .random {
			e.args = [LExpr(1), LExpr(10)]
		}
		if op == .inDim { e.s = "overworld" }
		if op == .inBiome { e.v = Double(Biome.plains.rawValue) }
		return e
	}
}

/// The Mod Test tools' LOGIC tab: what is running, the variables, the log, messages to send, and the
/// step debugger (pause every script, then run them one step at a time)
struct LogicDebugView: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	@State var rev: Int = 0

	var body: some View {
		let rt: LogicRT = ModRuntime.shared.logic
		let none: Bool = rt.isEmpty
		return VStack(alignment: .leading, spacing: 8) {
			if none { Text("This world's mods have no scripts.").font(.pixel(12)).foregroundColor(ModUI.dim) }
			controls
			counts
			running
			variables
			messages
			logLines
		}
	}

	var controls: some View {
		let vm: LogicVM = game.logic
		let paused: Bool = vm.paused
		let runTitle: String = paused ? "RUN" : "PAUSE"
		let runCol: Color = paused ? ModUI.accent : Color(ui: 0x8A6A2A)
		return HStack(spacing: 8) {
			SmallButton(title: runTitle, color: runCol) { self.pause() }
			if paused { SmallButton(title: "STEP", color: ModUI.blue) { self.step() } }
			SmallButton(title: "WORLD START AGAIN", color: ModUI.blue) { self.restart() }
			SmallButton(title: "REFRESH", color: Color(ui: 0x555555)) { self.rev += 1 }
		}
	}

	func pause() {
		game.logicPauseToggle()
		rev += 1
	}

	func step() {
		game.logicStepOnce()
		rev += 1
	}

	func restart() {
		game.logic.started = false
		rev += 1
	}

	var counts: some View {
		let vm: LogicVM = game.logic
		let line: String = joinText("Started ", String(vm.ran), " times \u{00B7} problems ", String(vm.errors))
		let head: String = joinText("RUNNING (", String(vm.threads.count), ")")
		return VStack(alignment: .leading, spacing: 4) {
			Text(verbatim: line).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			Text(verbatim: head).font(.pixel(12, .bold)).foregroundColor(ModUI.gold)
		}
	}

	var running: some View {
		let lines: [String] = game.logic.threads.map { LogicDebugView.threadLine($0) }
		return ForEach(0..<lines.count, id: \.self) { i in
			Text(verbatim: lines[i]).font(.pixel(11, .semibold)).foregroundColor(Color.white)
		}
	}

	static func threadLine(_ t: LThread) -> String {
		let wait: String = t.waitT > 0 ? String(format: " \u{00B7} waiting %.1f s", t.waitT) : ""
		let who: String = t.hasMob ? " \u{00B7} creature" : ""
		return joinText(t.whereText, wait, who)
	}

	var variables: some View {
		let keys: [String] = game.logicVars.keys.sorted()
		let lines: [String] = keys.map { k in joinText(k, " = ", String(format: "%.2f", self.game.logicVars[k] ?? 0)) }
		return VStack(alignment: .leading, spacing: 4) {
			if !lines.isEmpty {
				Text("VARIABLES").font(.pixel(12, .bold)).foregroundColor(ModUI.gold)
				ForEach(0..<lines.count, id: \.self) { i in
					Text(verbatim: lines[i]).font(.pixel(11, .semibold)).foregroundColor(Color.white)
				}
			}
		}
	}

	var messages: some View {
		let msgs: [String] = Array(Set(ModRuntime.shared.logic.listeners(.custom).map { $0.def.evText })).sorted()
		return VStack(alignment: .leading, spacing: 4) {
			if !msgs.isEmpty {
				Text("SEND A MESSAGE").font(.pixel(12, .bold)).foregroundColor(ModUI.gold)
				HStack(spacing: 6) {
					ForEach(msgs, id: \.self) { m in self.messageButton(m) }
				}
			}
		}
	}

	func messageButton(_ m: String) -> some View {
		let title: String = m.isEmpty ? "(unnamed)" : m
		return SmallButton(title: title, color: Color(ui: 0x8A6A2A)) {
			self.game.fireLogic(.custom, text: m)
			self.rev += 1
		}
	}

	var logLines: some View {
		let log: [String] = Array(game.logic.log.suffix(30).reversed())
		return VStack(alignment: .leading, spacing: 2) {
			Text("LOG (newest first)").font(.pixel(12, .bold)).foregroundColor(ModUI.gold)
			ForEach(0..<log.count, id: \.self) { i in
				Text(verbatim: log[i]).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.85))
			}
		}
	}
}

// MARK: - Mod Creator: rules, weather, vehicles and the look of the screens

/// The WORLD tab: the rules of the game, what a new world starts with, and the Overworld's weather
struct WorldRulesView: View {
	@ObservedObject var s: ModSession
	@State var picking: Bool = false

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Change how the game plays in the worlds this mod is in. Each rule stays the game's own until you change it; when two mods change the same rule, the one lower in the mod list wins.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			rulesSection
			startSection
			WeatherRulesEditor(s: s)
		}
		.modCover(s, picking ? 1 : nil) { self.itemPicker }
	}

	var rulesSection: some View {
		ModSection(title: "RULES OF THE GAME") {
			ForEach(GameRule.allCases, id: \.self) { (r: GameRule) in self.ruleRow(r) }
		}
	}

	func ruleRow(_ r: GameRule) -> some View {
		let sp: GameRule.Spec = r.spec
		let v: Double? = s.mod.rules[sp.id]
		let set: Bool = v != nil
		let shown: String = WorldRulesView.valueText(sp, v ?? sp.def)
		let label: String = set ? shown : joinText("game's: ", shown)
		return VStack(alignment: .leading, spacing: 3) {
			HStack(spacing: 8) {
				Text(verbatim: sp.name).font(.pixel(13, .bold)).foregroundColor(Color.white)
				Spacer(minLength: 0)
				Text(verbatim: label).font(.pixel(12)).foregroundColor(set ? ModUI.gold : ModUI.dim)
				SmallButton(title: set ? "GAME'S" : "CHANGE", color: set ? ModUI.red : ModUI.blue) { self.toggleRule(sp) }
			}
			Text(verbatim: sp.help).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			if set { ruleControl(sp) }
		}
		.padding(.vertical, 3)
	}

	@ViewBuilder
	func ruleControl(_ sp: GameRule.Spec) -> some View {
		if sp.unit == "on" {
			ModToggle(label: sp.name, isOn: onBind(sp))
		} else {
			Slider(value: ruleBind(sp), in: sp.lo...sp.hi, step: sp.step).frame(minHeight: 34)
		}
	}

	static func valueText(_ sp: GameRule.Spec, _ v: Double) -> String {
		switch sp.unit {
		case "on": return v >= 0.5 ? "ON" : "OFF"
		case "x": return String(format: "x%.1f", v)
		case "min": return String(format: "%.0f min", v)
		default: return String(format: "%.0f", v)
		}
	}

	func toggleRule(_ sp: GameRule.Spec) {
		if s.mod.rules[sp.id] != nil { s.mod.rules[sp.id] = nil } else { s.mod.rules[sp.id] = sp.def }
		s.touch()
	}

	func ruleBind(_ sp: GameRule.Spec) -> Binding<Double> {
		let ses: ModSession = s
		let id: String = sp.id
		let d: Double = sp.def
		return Binding<Double>(get: { ses.mod.rules[id] ?? d }, set: { (v: Double) in
			ses.mod.rules[id] = v
			ses.touch()
		})
	}

	func onBind(_ sp: GameRule.Spec) -> Binding<Bool> {
		let base: Binding<Double> = ruleBind(sp)
		return Binding<Bool>(get: { base.wrappedValue >= 0.5 }, set: { (on: Bool) in base.wrappedValue = on ? 1 : 0 })
	}

	var startSection: some View {
		let can: Bool = s.mod.startItems.count < ModWorldLimits.startItems
		return ModSection(title: "A NEW WORLD STARTS WITH", help: "Put in the bag of every new world (not in creative), beside the game's four torches.") {
			ForEach(0..<s.mod.startItems.count, id: \.self) { (i: Int) in self.startRow(i) }
			if can { SmallButton(title: "+ ADD AN ITEM", color: ModUI.accent) { self.picking = true } }
		}
	}

	func startRow(_ i: Int) -> some View {
		let c: ModCost = s.mod.startItems[i]
		let name: String = ModPreview.name(c.item, s.catalog)
		return HStack(spacing: 8) {
			ModPreview.icon(c.item, s.catalog).resizable().interpolation(.none).frame(width: 32, height: 32)
			Text(verbatim: name).font(.pixel(13)).foregroundColor(Color.white).lineLimit(1)
			Spacer(minLength: 0)
			SmallButton(title: "-", color: ModUI.blue) { self.addCount(i, c.n >= 20 ? -10 : -1) }
			Text(verbatim: String(c.n)).font(.pixel(14)).foregroundColor(ModUI.gold).frame(minWidth: 34)
			SmallButton(title: "+", color: ModUI.blue) { self.addCount(i, c.n >= 10 ? 10 : 1) }
			SmallButton(title: "\u{2715}", color: ModUI.red) { self.removeStart(i) }
		}
	}

	func addCount(_ i: Int, _ d: Int) {
		if i < 0 || i >= s.mod.startItems.count { return }
		s.mod.startItems[i].n = clampI(s.mod.startItems[i].n + d, 1, 999)
		s.touch()
	}

	func removeStart(_ i: Int) {
		if i < 0 || i >= s.mod.startItems.count { return }
		s.mod.startItems.remove(at: i)
		s.touch()
	}

	var itemPicker: some View {
		ItemPickerView(catalog: s.catalog, title: "A NEW WORLD STARTS WITH...", pick: { (it: Item) in
			self.s.mod.startItems.append(ModCost(it, 1))
			self.s.touch()
			self.picking = false
		}, cancel: { self.picking = false })
	}
}

/// The Overworld's weather as the mod has it: how often each kind comes, how strong and how long
struct WeatherRulesEditor: View {
	@ObservedObject var s: ModSession

	var body: some View {
		let on: Bool = s.mod.weather != nil
		return ModSection(title: "THE OVERWORLD'S WEATHER", help: "How often each kind of weather comes (1: as the game, 0: never), how hard it rains and blows, and how long each spell lasts. The weather switches in Settings still apply.") {
			ModToggle(label: "Change the weather", help: on ? "This mod's weather is used" : "The game's weather", isOn: onBind)
			if on { controls }
		}
	}

	var controls: some View {
		VStack(alignment: .leading, spacing: 6) {
			ForEach(WeatherKind.allCases, id: \.self) { (k: WeatherKind) in
				StatSlider(label: k.name, value: self.chanceBind(k), range: 0.0...5.0, step: 0.25, format: "x%.2f")
			}
			StatSlider(label: "Rain and snow", value: numBind(\ModWeather.rain), range: 0.0...3.0, step: 0.1, format: "x%.1f")
			StatSlider(label: "Wind", value: numBind(\ModWeather.wind), range: 0.0...3.0, step: 0.1, format: "x%.1f")
			StatSlider(label: "How long spells last", value: numBind(\ModWeather.length), range: 0.25...6.0, step: 0.25, format: "x%.2f")
			ModColorRow(label: "Colour of the rain", color: rainBind)
			SmallButton(title: "THE GAME'S RAIN COLOUR") { self.edit { (w: inout ModWeather) in w.rainColor = 0 } }
		}
	}

	func edit(_ f: (inout ModWeather) -> Void) {
		var w: ModWeather = s.mod.weather ?? ModWeather()
		f(&w)
		s.mod.weather = w
		s.touch()
	}

	var onBind: Binding<Bool> {
		let ses: ModSession = s
		return Binding<Bool>(get: { ses.mod.weather != nil }, set: { (on: Bool) in
			ses.mod.weather = on ? (ses.mod.weather ?? ModWeather()) : nil
			ses.touch()
		})
	}

	func chanceBind(_ k: WeatherKind) -> Binding<Double> {
		let ses: ModSession = s
		return Binding<Double>(get: { ses.mod.weather?.chanceOf(k) ?? 1 }, set: { (v: Double) in
			var w: ModWeather = ses.mod.weather ?? ModWeather()
			while w.chance.count < WeatherKind.allCases.count { w.chance.append(1) }
			w.chance[k.rawValue] = v
			ses.mod.weather = w
			ses.touch()
		})
	}

	func numBind(_ kp: WritableKeyPath<ModWeather, Double>) -> Binding<Double> {
		let ses: ModSession = s
		return Binding<Double>(get: { (ses.mod.weather ?? ModWeather())[keyPath: kp] }, set: { (v: Double) in
			var w: ModWeather = ses.mod.weather ?? ModWeather()
			w[keyPath: kp] = v
			ses.mod.weather = w
			ses.touch()
		})
	}

	var rainBind: Binding<UInt32> {
		let ses: ModSession = s
		return Binding<UInt32>(get: { ses.mod.weather?.rainColor ?? 0 }, set: { (v: UInt32) in
			var w: ModWeather = ses.mod.weather ?? ModWeather()
			w.rainColor = v
			ses.mod.weather = w
			ses.touch()
		})
	}
}

extension BlockEditorView {
	/// As building material, and on power lines
	var buildSection: some View {
		let p: ModBlock = block
		let auto: BlockPhys = blockPhysFrom(TileDef(name: p.name, hard: p.hardness, solid: p.collision == .solid))
		let weightNote: String = String(format: "0 = worked out from its hardness (%.1f, holds %.0f)", auto.weight, auto.carry)
		return VStack(spacing: 10) {
			ModSection(title: "AS BUILDING MATERIAL", help: weightNote) {
				StatSlider(label: "Weight (stone is 2.5)", value: b(\.weight, 0), range: 0.0...(s.mod.sandbox ? 40 : 12), step: 0.1, format: "%.1f")
				StatSlider(label: "Weight it holds up", value: b(\.carry, 0), range: 0.0...(s.mod.sandbox ? 4000 : 400), step: 5, format: "%.0f")
				ModToggle(label: "Falls like sand", help: "With nothing under it, it drops and lands", isOn: b(\.falls, false))
				StatSlider(label: "Grip (stone is 1, ice 0.12)", value: b(\.grip, 1.0), range: 0.02...(s.mod.sandbox ? 4.0 : 2.0), step: 0.02, format: "%.2f")
				StatSlider(label: "Bounce (0 none, hay 0.3)", value: b(\.bounce, 0.0), range: 0.0...(s.mod.sandbox ? 1.2 : 0.9), step: 0.05, format: "%.2f")
			}
			ModSection(title: "ON POWER LINES", help: p.powerRole.help) {
				ChoiceRows(options: ModPowerRole.allCases.map { $0.name }, selected: powerBind, columns: 3)
				if p.powerRole != .none && p.powerRole != .signal {
					StatSlider(label: "Strength (sparks a second)", value: b(\.powerAmt, 4), range: 0.1...(s.mod.sandbox ? 200 : 40), step: 0.1, format: "%.1f")
				}
			}
			if p.collision == .liquid { liquidSection }
		}
	}

	/// A liquid's numbers (collision: Liquid)
	var liquidSection: some View {
		let sb: Bool = s.mod.sandbox
		return ModSection(title: "AS A LIQUID", help: "Water is density 1 and thickness 1; lava is 3.1 and 4. A part-full cell is drawn in the block's colour, this see-through.") {
			StatSlider(label: "Density (what floats in it)", value: b(\.liqDensity, 1.0), range: 0.2...(sb ? 12.0 : 5.0), step: 0.05, format: "%.2f")
			StatSlider(label: "Thickness (how slowly it flows)", value: b(\.liqThick, 1.0), range: 1.0...(sb ? 20.0 : 8.0), step: 1, format: "%.0f")
			StatSlider(label: "Spreads (blocks over flat ground)", value: reachBind, range: 1.0...(sb ? 30.0 : 12.0), step: 1, format: "%.0f")
			StatSlider(label: "See-through (1 is solid colour)", value: b(\.liqOpacity, 0.75), range: 0.1...1.0, step: 0.05, format: "%.2f")
			StatSlider(label: "Harm a second to who is in it", value: b(\.liqHarm, 0), range: 0.0...(sb ? 100.0 : 20.0), step: 0.5, format: "%.1f")
			ModToggle(label: "Burns (like lava)", help: "Whoever is in it is set alight; a vehicle floats on it", isOn: b(\.liqHot, false))
			ModToggle(label: "Dries up", help: "A thin film of it left alone evaporates", isOn: b(\.liqDries, false))
			Text("Hardens into, where it meets another liquid").font(.pixel(12, .bold)).foregroundColor(Color(ui: 0xFFFFFF))
			ChoiceRows(options: BlockEditorView.hardenNames, selected: hardenBind, columns: 4)
			Text("Gives whoever is in it").font(.pixel(12, .bold)).foregroundColor(Color(ui: 0xFFFFFF))
			ChoiceRows(options: ["Nothing"] + ModEffectKind.allCases.map { $0.name }, selected: effectBind, columns: 3)
			if block.liqEffect >= 0 {
				StatSlider(label: "Effect strength", value: b(\.liqEffectAmt, 10), range: 0.0...(sb ? 200.0 : 60.0), step: 1, format: "%.0f")
			}
		}
	}

	static let hardenNames: [String] = ["Nothing", "Stone", "Obsidian", "Glass", "Ice", "Sand", "Dirt", "Ash Stone"]
	static let hardenKeys: [String] = ["", BlockEditorView.tileKey(.stone), BlockEditorView.tileKey(.obsidian), BlockEditorView.tileKey(.glass), BlockEditorView.tileKey(.ice), BlockEditorView.tileKey(.sand), BlockEditorView.tileKey(.dirt), BlockEditorView.tileKey(.ashStone)]

	static func tileKey(_ t: Tile) -> String { return "tile:" + String(t.rawValue) }

	var hardenBind: Binding<Int> {
		let base: Binding<String> = b(\.liqHardens, "")
		return Binding<Int>(get: { BlockEditorView.hardenKeys.firstIndex(of: base.wrappedValue) ?? 0 }, set: { (i: Int) in base.wrappedValue = BlockEditorView.hardenKeys[clampI(i, 0, BlockEditorView.hardenKeys.count - 1)] })
	}

	var effectBind: Binding<Int> {
		let base: Binding<Int> = b(\.liqEffect, -1)
		return Binding<Int>(get: { base.wrappedValue + 1 }, set: { (i: Int) in base.wrappedValue = i - 1 })
	}

	var reachBind: Binding<Double> {
		let base: Binding<Int> = b(\.liqReach, 7)
		return Binding<Double>(get: { Double(base.wrappedValue) }, set: { (v: Double) in base.wrappedValue = Int(v.rounded()) })
	}

	var powerBind: Binding<Int> {
		let base: Binding<ModPowerRole> = b(\.powerRole, .none)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { base.wrappedValue = ModPowerRole(rawValue: $0) ?? .none })
	}
}

/// The VEHICLES tab: whole vehicles, each also an item (its kit) that builds it
struct VehicleListView: View {
	@ObservedObject var s: ModSession
	var open: (String) -> Void

	var body: some View {
		let can: Bool = s.mod.vehicles.count < ModWorldLimits.vehicles
		return VStack(alignment: .leading, spacing: 8) {
			Text("A vehicle kept in the mod is built from its kit: an item your recipes make. Use the kit on open ground (or water, for a boat) and the vehicle is there to drive. Paint it part by part here, or build it in a TEST world and keep it with SAVE VEHICLE on the TEST panel.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			if can { PixelButton(title: "+ NEW VEHICLE", color: ModUI.accent) { self.add() } }
			ForEach(s.mod.vehicles) { (v: ModVehicle) in self.row(v) }
		}
	}

	func row(_ v: ModVehicle) -> some View {
		let pic: Image = pixImage(ModRuntime.shared.vehicleIconBuf(v))
		let line: String = joinText(String(v.cells.count), " parts", v.water ? " · a boat" : "")
		return ModRow(image: pic, title: v.name, sub: line, open: { self.open(v.id) }, copy: { self.copy(v) },
					  delete: { self.s.mod.vehicles.removeAll { $0.id == v.id }; self.s.touch() },
					  off: s.mod.off.contains(v.id), toggle: { self.toggleOff(v.id) })
	}

	func add() {
		var v = ModVehicle()
		v.id = s.mod.freshID("veh")
		v.name = joinText("Vehicle ", String(s.mod.vehicles.count + 1))
		v.cells = [ModVehicleCell(1, 0, .seat), ModVehicleCell(2, 0, .steering), ModVehicleCell(0, 1, .fuelTank), ModVehicleCell(1, 1, .frame),
				   ModVehicleCell(2, 1, .frame), ModVehicleCell(3, 1, .engine), ModVehicleCell(0, 2, .wheel), ModVehicleCell(3, 2, .wheel)]
		s.mod.vehicles.append(v)
		s.touch()
		open(v.id)
	}

	func copy(_ v: ModVehicle) {
		if s.mod.vehicles.count >= ModWorldLimits.vehicles { return }
		var c: ModVehicle = v
		c.id = s.mod.freshID("veh")
		c.name = joinText(v.name, " copy")
		s.mod.vehicles.append(c)
		s.touch()
	}

	func toggleOff(_ id: String) {
		if s.mod.off.contains(id) { s.mod.off.removeAll { $0 == id } } else { s.mod.off.append(id) }
		s.touch()
	}
}

/// Editing one vehicle: its name, whether it is a boat, its fuel, and its parts painted on a grid
struct VehicleEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var brush: Int = 0
	@State var block: String = ""
	@State var picking: Bool = false

	func b<T>(_ kp: WritableKeyPath<ModVehicle, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.vehicles, id, kp, d) }
	var veh: ModVehicle { return s.mod.vehicles.first { $0.id == id } ?? ModVehicle() }

	/// what the brush can paint: every part but a plain block, then a block, then nothing
	static let parts: [PartType] = PartType.allCases.filter { $0 != .block }
	static var brushNames: [String] { return parts.map { $0.name.uppercased() } + ["BLOCK", "ERASE"] }

	var body: some View {
		let v: ModVehicle = veh
		return VStack(spacing: 10) {
			ModSection(title: v.name.uppercased(), help: "Its kit is an item: give it a recipe on the RECIPES tab.") {
				ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Sky Hauler")
				ModTextField(label: "Description", text: b(\.desc, ""), placeholder: "Optional")
				ModToggle(label: "A boat", help: "Put down on water instead of on the ground", isOn: b(\.water, false))
				StatSlider(label: "Fuel it comes with", value: b(\.fuel, 40), range: 0.0...400.0, step: 5, format: "%.0f")
			}
			ModSection(title: "PARTS", help: brushHelp) {
				ChoiceRows(options: VehicleEditorView.brushNames, selected: $brush, columns: 5)
				if brush == VehicleEditorView.parts.count { blockChoice }
				grid(v)
				Text(verbatim: joinText(String(v.cells.count), " of ", String(ModVehicle.maxCells), " cells")).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				SmallButton(title: "CLEAR", color: ModUI.red) { self.b(\.cells, []).wrappedValue = [] }
			}
			ModSection(title: "ICON", help: "Blank: drawn from its parts.") {
				PixelEditorView(pixels: b(\.icon, ModPixels(w: 12, h: 12)), maxSide: 220, outlineDefault: true)
			}
		}
		.modCover(s, picking ? 1 : nil) { self.blockPicker }
	}

	var brushHelp: String {
		if brush < VehicleEditorView.parts.count { return joinText("Tap or drag to place: ", VehicleEditorView.parts[brush].name, ". Wheels go at the bottom, a seat or cockpit is where the driver sits.") }
		if brush == VehicleEditorView.parts.count { return "Tap or drag to place the chosen block (a mod block that works as a vehicle part works as one)." }
		return "Tap or drag to take parts away."
	}

	var blockChoice: some View {
		let label: String = block.isEmpty ? "No block chosen" : blockName(block)
		return HStack(spacing: 8) {
			Text(verbatim: label).font(.pixel(12)).foregroundColor(Color.white)
			Spacer(minLength: 0)
			SmallButton(title: "CHOOSE A BLOCK...", color: ModUI.blue) { self.picking = true }
		}
	}

	func blockName(_ k: String) -> String {
		if k.hasPrefix("tile:"), let n = Int(k.dropFirst(5)), let t = Tile(rawValue: UInt8(clampI(n, 0, 255))) { return t.name }
		return s.catalog.names[k] ?? k
	}

	var blockPicker: some View {
		ItemPickerView(catalog: s.catalog, title: "BUILD WITH...", blocksOnly: true, pick: { (it: Item) in
			switch it {
			case .block(let t): self.block = joinText("tile:", String(t.rawValue))
			case .custom(let k): self.block = k
			default: break
			}
			self.picking = false
		}, cancel: { self.picking = false })
	}

	func grid(_ v: ModVehicle) -> some View {
		let n: Int = ModVehicle.maxSize
		let cell: CGFloat = 13
		let side: CGFloat = cell * CGFloat(n)
		var colours: [Int: UInt32] = [:]
		for c in v.cells { colours[c.y * n + c.x] = ModRuntime.shared.vehicleCellColor(c) }
		return Canvas { ctx, size in
			for y in 0..<n {
				for x in 0..<n {
					let r: CGRect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell - 1, height: cell - 1)
					let col: UInt32 = colours[y * n + x] ?? 0x1A2030
					ctx.fill(Path(r), with: .color(Color(hex: col)))
				}
			}
		}
		.frame(width: side, height: side)
		.gesture(DragGesture(minimumDistance: 0).onChanged { (g: DragGesture.Value) in self.paint(g.location, cell) })
	}

	func paint(_ p: CGPoint, _ cell: CGFloat) {
		let x: Int = Int(floor(p.x / cell))
		let y: Int = Int(floor(p.y / cell))
		let n: Int = ModVehicle.maxSize
		if x < 0 || y < 0 || x >= n || y >= n { return }
		var cells: [ModVehicleCell] = veh.cells
		let had: Int? = cells.firstIndex { $0.x == x && $0.y == y }
		let partCount: Int = VehicleEditorView.parts.count
		if brush > partCount {
			guard let i = had else { return }
			cells.remove(at: i)
		} else {
			var c = ModVehicleCell(x, y, .frame)
			if brush < partCount {
				c.part = VehicleEditorView.parts[brush].rawValue
			} else {
				if block.isEmpty { return }
				c.block = block
			}
			if let i = had {
				if cells[i] == c { return }
				cells[i] = c
			} else {
				if cells.count >= ModVehicle.maxCells { return }
				cells.append(c)
			}
		}
		b(\.cells, []).wrappedValue = cells
	}
}

extension ModTestPanel {
	/// In a TEST world: keeps the vehicle the player drives (or stands by) in the mod as a design
	func saveVehicle() -> String {
		let mid: String = game.testMod
		guard !mid.isEmpty, var p = ModStore.pack(mid) else { return "Only in a TEST world." }
		guard let v = game.inVehicle ?? game.nearestVehicle(3) else { return "Stand by a vehicle (or drive one) first." }
		if p.vehicles.count >= ModWorldLimits.vehicles { return joinText(p.name, " already holds the most vehicles a mod can.") }
		var mv: ModVehicle = game.vehicleDesign(v)
		mv.id = p.freshID("veh")
		mv.name = joinText("Vehicle ", String(p.vehicles.count + 1))
		p.vehicles.append(mv)
		return ModStore.save(p) ? joinText("Saved as \u{201C}", mv.name, "\u{201D} in ", p.name, ": give its kit a recipe in the Mod Creator.") : "The mod could not be saved."
	}
}

/// The LOOK tab: how the game's screens look while this mod is on (the theme of the last mod in the
/// list that has one is used, on the title screen too)
struct ThemeEditorView: View {
	@ObservedObject var s: ModSession

	var body: some View {
		let on: Bool = s.mod.theme != nil
		return VStack(alignment: .leading, spacing: 10) {
			Text("Change the colours of the game's screens and buttons, the letters, how round the buttons are, the title screen, and the size and sides of the touch controls. It shows once the mod is switched on, from the title screen.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ModToggle(label: "Change how the game looks", help: on ? "This mod's look" : "The game's own look", isOn: onBind)
			if on { sections }
		}
	}

	var sections: some View {
		let t: ModTheme = s.mod.theme ?? ModTheme()
		return VStack(alignment: .leading, spacing: 10) {
			ThemePreview(theme: t)
			ModSection(title: "COLOURS", help: "Each takes the place of the game's colour for that part of every screen (other shades follow it).") {
				ForEach(ThemeRole.allCases, id: \.self) { (r: ThemeRole) in self.roleRow(r) }
				StatSlider(label: "How much everything else leans to the tint", value: numBind(\ModTheme.tintAmt), range: 0.0...1.0, step: 0.05, format: "%.2f")
			}
			ModSection(title: "LETTERS AND BUTTONS") {
				ChoiceRows(options: ModTheme.fonts, selected: intBind(\ModTheme.font), columns: 4)
				StatSlider(label: "Rounded corners", value: numBind(\ModTheme.corner), range: 0.0...16.0, step: 1, format: "%.0f")
				ModColorRow(label: "Outline", color: colorBind(\ModTheme.outline))
			}
			ModSection(title: "TITLE SCREEN", help: "Blank: the game's own title and the sky behind it.") {
				ModTextField(label: "Title", text: textBind(\ModTheme.title), placeholder: "PIXEL REALM")
				ModTextField(label: "Words under it", text: textBind(\ModTheme.subtitle), placeholder: "A new splash line each time")
				PixelEditorView(pixels: backBind, maxSide: 300, outlineDefault: false)
				HStack(spacing: 8) {
					SmallButton(title: "PAINT A BACKGROUND", color: ModUI.blue) { self.backBind.wrappedValue = ModPixels(w: 48, h: 27) }
					SmallButton(title: "NO PICTURE", color: ModUI.red) { self.backBind.wrappedValue = ModPixels(w: 1, h: 1) }
				}
			}
			ModSection(title: "TOUCH CONTROLS") {
				StatSlider(label: "Size", value: numBind(\ModTheme.hudScale), range: 0.6...1.5, step: 0.05, format: "x%.2f")
				StatSlider(label: "How solid", value: numBind(\ModTheme.hudAlpha), range: 0.3...1.0, step: 0.05, format: "%.2f")
				ModToggle(label: "Swap sides", help: "Attack stick and JUMP on the left, the walking stick on the right", isOn: boolBind(\ModTheme.swapSides))
			}
		}
	}

	func roleRow(_ r: ThemeRole) -> some View {
		let c: UInt32 = (s.mod.theme ?? ModTheme()).color(r)
		return VStack(alignment: .leading, spacing: 4) {
			ModColorRow(label: c == 0 ? joinText(r.name, " (the game's)") : r.name, color: roleBind(r))
			if c != 0 { SmallButton(title: "THE GAME'S", color: ModUI.red) { self.edit { (t: inout ModTheme) in t.colors[r.rawValue] = 0 } } }
		}
	}

	func edit(_ f: (inout ModTheme) -> Void) {
		var t: ModTheme = s.mod.theme ?? ModTheme()
		while t.colors.count < ThemeRole.allCases.count { t.colors.append(0) }
		f(&t)
		s.mod.theme = t
		s.touch()
	}

	var onBind: Binding<Bool> {
		let ses: ModSession = s
		return Binding<Bool>(get: { ses.mod.theme != nil }, set: { (on: Bool) in
			ses.mod.theme = on ? (ses.mod.theme ?? ModTheme()) : nil
			ses.touch()
		})
	}

	func roleBind(_ r: ThemeRole) -> Binding<UInt32> {
		let ses: ModSession = s
		return Binding<UInt32>(get: { (ses.mod.theme ?? ModTheme()).color(r) }, set: { (v: UInt32) in
			var t: ModTheme = ses.mod.theme ?? ModTheme()
			while t.colors.count < ThemeRole.allCases.count { t.colors.append(0) }
			t.colors[r.rawValue] = v
			ses.mod.theme = t
			ses.touch()
		})
	}

	func field<T>(_ kp: WritableKeyPath<ModTheme, T>) -> Binding<T> {
		let ses: ModSession = s
		return Binding<T>(get: { (ses.mod.theme ?? ModTheme())[keyPath: kp] }, set: { (v: T) in
			var t: ModTheme = ses.mod.theme ?? ModTheme()
			t[keyPath: kp] = v
			ses.mod.theme = t
			ses.touch()
		})
	}

	func numBind(_ kp: WritableKeyPath<ModTheme, Double>) -> Binding<Double> { return field(kp) }
	func intBind(_ kp: WritableKeyPath<ModTheme, Int>) -> Binding<Int> { return field(kp) }
	func textBind(_ kp: WritableKeyPath<ModTheme, String>) -> Binding<String> { return field(kp) }
	func boolBind(_ kp: WritableKeyPath<ModTheme, Bool>) -> Binding<Bool> { return field(kp) }
	func colorBind(_ kp: WritableKeyPath<ModTheme, UInt32>) -> Binding<UInt32> { return field(kp) }
	var backBind: Binding<ModPixels> { return field(\ModTheme.background) }
}

/// A few buttons and a title in a theme's colours (drawn from the theme itself, before it is switched on)
struct ThemePreview: View {
	let theme: ModTheme

	func col(_ r: ThemeRole) -> Color {
		let c: UInt32 = theme.color(r)
		return Color(hex: c != 0 ? c : r.gameColor)
	}

	var body: some View {
		let design: Font.Design = [Font.Design.monospaced, .rounded, .serif, .default][clampI(theme.font, 0, 3)]
		let r: CGFloat = CGFloat(theme.corner)
		let title: String = theme.title.isEmpty ? "PIXEL REALM" : theme.title
		return VStack(spacing: 8) {
			Text(verbatim: title).font(.system(size: 22, weight: .black, design: design)).foregroundColor(col(.titles))
			HStack(spacing: 6) {
				sample("PLAY", col(.accept), r, design)
				sample("BAG", col(.buttons), r, design)
				sample("INFO", col(.info), r, design)
				sample("QUIT", col(.danger), r, design)
			}
		}
		.padding(10)
		.frame(maxWidth: .infinity)
		.background(RoundedRectangle(cornerRadius: r).fill(col(.panels)))
	}

	func sample(_ t: String, _ c: Color, _ r: CGFloat, _ d: Font.Design) -> some View {
		return Text(verbatim: t)
			.font(.system(size: 13, weight: .heavy, design: d))
			.foregroundColor(Color.white)
			.padding(.horizontal, 10)
			.padding(.vertical, 8)
			.background(RoundedRectangle(cornerRadius: r).fill(c))
			.overlay(RoundedRectangle(cornerRadius: r).stroke(Color(hex: theme.outline), lineWidth: 2))
	}
}
