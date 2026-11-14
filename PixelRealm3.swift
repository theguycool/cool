// PIXEL REALM v2, part 3 of 10: the hand-drawn pictures kept as text, creatures and their kinds, vehicles, the game state, the player and input.
// The game is 10 files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm10.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
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
