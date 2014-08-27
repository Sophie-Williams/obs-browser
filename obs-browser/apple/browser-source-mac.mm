/******************************************************************************
 Copyright (C) 2014 by John R. Bradley <jrb@turrettech.com>

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 2 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
 ******************************************************************************/

#include <Foundation/Foundation.h>
#include <memory>
#include <map>

#import "cef-logging.h"

#include "browser-source.hpp"
#include "browser-listener.hpp"
#include "browser-manager.hpp"

#include "browser-source-mac.h"
#include "browser-source-listener-mac.h"

#include "texture-ref.hpp"

extern "C" {
#include "graphics-helpers.h"
}

BrowserSource::BrowserSource(obs_data_t settings, obs_source_t source)
:  pimpl(new Impl(this)), source(source)
{
	UpdateSettings(settings);
}


BrowserSource::~BrowserSource()
{
	if (browserIdentifier != 0) {
		BrowserManager::Instance()->DestroyBrowser(browserIdentifier);
	}
	pthread_mutex_destroy(&textureLock);
}

BrowserSource::Impl::Impl(BrowserSource *parent)
: parent(parent), activeTexture(nullptr)
{
	obs_enter_graphics();

	char *drawEffectFile = obs_module_file("draw_rect.effect");
	drawEffect = gs_effect_create_from_file(drawEffectFile, NULL);
	bfree(drawEffectFile);

	struct gs_sampler_info info = {
		.filter = GS_FILTER_LINEAR,
		.address_u = GS_ADDRESS_CLAMP,
		.address_v = GS_ADDRESS_CLAMP,
		.address_w = GS_ADDRESS_CLAMP,
		.max_anisotropy = 1,
	};
	sampler = gs_samplerstate_create(&info);
	vertexBuffer = create_vertex_buffer();

	obs_leave_graphics();
}

BrowserSource::Impl::~Impl()
{
	obs_enter_graphics();
	if (vertexBuffer != nullptr) {
		gs_vertexbuffer_destroy(vertexBuffer);
		vertexBuffer = nullptr;
	}
	if (sampler != nullptr) {
		gs_samplerstate_destroy(sampler);
		sampler = nullptr;
	}
	if (drawEffect != nullptr) {
		gs_effect_destroy(drawEffect);
		drawEffect = nullptr;
	}
	obs_leave_graphics();
}

std::shared_ptr<BrowserListener>
BrowserSource::CreateListener()
{
	return pimpl->CreateListener();
}

void
BrowserSource::RenderActiveTexture()
{
	pimpl->RenderCurrentTexture();
}

void
BrowserSource::Impl::RenderCurrentTexture()
{
	GetParent()->LockTexture();

	build_sprite_rect(
		gs_vertexbuffer_get_data(vertexBuffer),
		0, 0, parent->GetWidth(), parent->GetHeight());

	if (activeTexture != nullptr) {
		gs_vertexbuffer_flush(vertexBuffer);
		gs_load_vertexbuffer(vertexBuffer);
		gs_load_indexbuffer(NULL);
		gs_load_samplerstate(sampler, 0);

		gs_technique_t tech = gs_effect_get_technique(
			drawEffect, "Default");
		gs_effect_set_texture(gs_effect_get_param_by_idx(
			drawEffect, 1), activeTexture->GetTexture());

		gs_technique_begin(tech);
		gs_technique_begin_pass(tech, 0);
		gs_draw(GS_TRISTRIP, 0, 4);

		gs_technique_end_pass(tech);
		gs_technique_end(tech);
	}
	
	GetParent()->UnlockTexture();
}

std::shared_ptr<BrowserListener>
BrowserSource::Impl::CreateListener()
{
	return std::shared_ptr<BrowserListener>(
		new BrowserSource::Impl::Listener(this));
}
